#!/usr/bin/env bash
# tools/impermanence.sh — operator CLI for Persist Extensions.
#
# Verbs: add <path>, remove [--yes] <path>, status, apply-defaults.
# Host config is the source of truth; the tool edits jsonc first, then
# materializes mount unit + tmpfiles + data move to match.
#
# Env overrides (for testing):
#   IMPERMANENCE_ROOT       default empty; prefixes live-fs paths
#   IMPERMANENCE_MOUNT      default /persist
#   IMPERMANENCE_MANIFEST   default /usr/lib/impermanence/defaults.manifest
#   IMPERMANENCE_PROFILE    Host Profile name (hosts/<name>/); default: the
#                           profile whose system.hostname (or dir name) is
#                           IMPERMANENCE_HOSTNAME
#   IMPERMANENCE_HOSTNAME   default $(hostname)
#   IMPERMANENCE_HOSTS_DIR  default <repo>/.installer/hosts
#   IMPERMANENCE_FILESYSTEM default: the live root's fstype (zfs | btrfs)

set -euo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../lib/jsonc.sh
source "$INSTALLER_DIR/lib/jsonc.sh"
# shellcheck source=../lib/impermanence-common.sh
source "$INSTALLER_DIR/lib/impermanence-common.sh"

: "${IMPERMANENCE_ROOT:=}"
: "${IMPERMANENCE_MOUNT:=/persist}"
: "${IMPERMANENCE_MANIFEST:=/usr/lib/impermanence/defaults.manifest}"
: "${IMPERMANENCE_HOSTNAME:=$(hostname)}"
: "${IMPERMANENCE_HOSTS_DIR:=$INSTALLER_DIR/hosts}"
: "${IMPERMANENCE_RPOOL:=rpool}"
# The root filesystem decides the rollback mechanics (zfs datasets vs btrfs
# subvolumes, ADR 0044); FILESYSTEM steers the shared mount-unit ordering.
: "${IMPERMANENCE_FILESYSTEM:=$(findmnt -n -o FSTYPE --target / 2>/dev/null)}"
export FILESYSTEM="$IMPERMANENCE_FILESYSTEM"

usage() {
  cat >&2 <<EOF
Usage: impermanence.sh <verb> [args]
  add <path>                 persist <path> across reboots
  remove [--yes] <path>      stop persisting <path>
                               --yes moves data back to live path
  status                     report active Persist Mounts and drift
  apply-defaults             reconcile curated defaults with manifest
EOF
}

require_enabled() {
  if [[ ! -d "$IMPERMANENCE_MOUNT" ]]; then
    echo "impermanence not enabled on this system (no $IMPERMANENCE_MOUNT)" >&2
    exit 1
  fi
}

require_absolute() {
  if [[ "$1" != /* ]]; then
    echo "path must be absolute: '$1'" >&2
    exit 2
  fi
}

require_no_trailing_slash() {
  if [[ "$1" != / && "$1" == */ ]]; then
    echo "path must not have trailing slash: '$1'" >&2
    exit 2
  fi
}

require_not_curated() {
  if [[ -f "$IMPERMANENCE_MANIFEST" ]] \
     && grep -qxF "$1" "$IMPERMANENCE_MANIFEST"; then
    echo "'$1' is a curated persist default; managed via apply-defaults" >&2
    exit 2
  fi
}

require_exists() {
  if [[ ! -e "${IMPERMANENCE_ROOT}$1" ]]; then
    echo "path does not exist on disk: '$1'" >&2
    exit 2
  fi
}

require_not_symlink() {
  if [[ -L "${IMPERMANENCE_ROOT}$1" ]]; then
    echo "path is a symlink; resolve to canonical path: '$1'" >&2
    exit 2
  fi
}

path_kind() {
  if [[ -d "${IMPERMANENCE_ROOT}$1" ]]; then echo d; else echo f; fi
}

unit_path() {
  local target="$1" escaped_path
  escaped_path="$(systemd-escape --path "$target")"
  echo "${IMPERMANENCE_ROOT}/usr/lib/systemd/system/$escaped_path.mount"
}

# The host's profile.jsonc (persist paths under .persist.*). Profile name and
# hostname are decoupled (ADR 0020): `desktop` installs hostname `eterniox`, so
# match system.hostname, defaulting to the dir name as the installer does.
host_profile_file() {
  local hosts_directory="$IMPERMANENCE_HOSTS_DIR" profile_file hostname_value
  if [[ -n "${IMPERMANENCE_PROFILE:-}" ]]; then
    for profile_file in \
        "$hosts_directory/$IMPERMANENCE_PROFILE/profile.jsonc" \
        "$hosts_directory/vm/$IMPERMANENCE_PROFILE/profile.jsonc"; do
      [[ -f "$profile_file" ]] && { echo "$profile_file"; return 0; }
    done
    return 1
  fi
  for profile_file in "$hosts_directory"/*/profile.jsonc \
                      "$hosts_directory"/vm/*/profile.jsonc; do
    [[ -f "$profile_file" ]] || continue
    hostname_value="$(jsonc_read_optional "$profile_file" .system.hostname)"
    [[ -n "$hostname_value" ]] \
      || hostname_value="$(profile_name "$profile_file")"
    [[ "$hostname_value" == "$IMPERMANENCE_HOSTNAME" ]] \
      && { echo "$profile_file"; return 0; }
  done
  return 1
}

# profile_name <profile-file> — the Host Profile name: the directory holding
# its profile.jsonc.
profile_name() {
  basename "$(dirname "$1")"
}

# Abort before any change when no profile matches: recording the path is what
# makes the persist survive a reinstall, so never skip it silently.
require_host_profile() {
  host_profile_file >/dev/null && return 0
  local profile_file want="hostname \"$IMPERMANENCE_HOSTNAME\""
  [[ -n "${IMPERMANENCE_PROFILE:-}" ]] && want="\"$IMPERMANENCE_PROFILE\""
  echo "impermanence: no Host Profile for $want" >&2
  echo "Set IMPERMANENCE_PROFILE to one of:" >&2
  for profile_file in "$IMPERMANENCE_HOSTS_DIR"/*/profile.jsonc \
                      "$IMPERMANENCE_HOSTS_DIR"/vm/*/profile.jsonc; do
    [[ -f "$profile_file" ]] && echo "  $(profile_name "$profile_file")" >&2
  done
  exit 2
}

declare_in_host_profile() {
  local target="$1" kind="$2" profile_file selector
  profile_file="$(host_profile_file)"
  [[ "$kind" == d ]] && selector='.persist.directories' \
    || selector='.persist.files'
  jsonc_append_to_array "$profile_file" "$selector" "$target"
}

undeclare_in_host_profile() {
  local target="$1" profile_file
  profile_file="$(host_profile_file)"
  jsonc_remove_from_array "$profile_file" '.persist.files' "$target"
  jsonc_remove_from_array "$profile_file" '.persist.directories' \
    "$target"
}

impermanence_add() {
  if [[ $# -lt 1 ]]; then
    echo "impermanence: add requires a path" >&2
    exit 2
  fi
  local target="$1" kind unit
  require_enabled
  require_absolute "$target"
  require_no_trailing_slash "$target"
  require_not_curated "$target"
  require_exists "$target"
  require_not_symlink "$target"
  require_host_profile
  unit="$(unit_path "$target")"
  if [[ -f "$unit" ]]; then
    echo "impermanence: '$target' is already persisted; no-op"
    return 0
  fi
  # Data left by `remove` without --yes: copying over it would nest the live
  # tree inside, and a failed add's cleanup would delete it.
  if [[ -e "$IMPERMANENCE_MOUNT$target" ]]; then
    echo "impermanence: $IMPERMANENCE_MOUNT$target already holds data (an" \
      "earlier remove without --yes?) — move or delete it, then re-run" >&2
    exit 2
  fi
  kind="$(path_kind "$target")"
  declare_in_host_profile "$target" "$kind"
  # Each step in turn; the first failure stops the rest.
  if ! (
    impermanence_common_persist_stage_in_copy "$target" || exit 1
    impermanence_common_persist_apply "$target" "$kind" || exit 1
    impermanence_common_link_wants "$target" \
      "${IMPERMANENCE_ROOT}/usr/lib/systemd/system/local-fs.target.wants" \
      || exit 1
    impermanence_common_persist_activate "$target"
  ); then
    impermanence_common_persist_unapply "$target"
    rm -rf "$IMPERMANENCE_MOUNT$target"
    undeclare_in_host_profile "$target"
    return 1
  fi
}

impermanence_remove() {
  local move_back=0 target=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) move_back=1; shift ;;
      *)     target="$1"; shift ;;
    esac
  done
  if [[ -z "$target" ]]; then
    echo "impermanence: remove requires a path" >&2
    exit 2
  fi
  require_enabled
  require_absolute "$target"
  require_no_trailing_slash "$target"
  require_not_curated "$target"
  require_host_profile
  local unit; unit="$(unit_path "$target")"
  if [[ ! -f "$unit" ]]; then
    echo "impermanence: '$target' is not persisted; no-op"
    return 0
  fi
  impermanence_common_persist_unapply "$target"
  undeclare_in_host_profile "$target"
  if (( move_back )); then
    impermanence_common_persist_restore_data "$target"
  fi
}

impermanence_status() {
  require_enabled
  local unit what fragment_path label
  # Persist Mounts are named <esc>.mount (systemd's .mount naming contract), so
  # they share no name prefix to glob. Identify them by their intrinsic marker:
  # a bind whose source (What=) lives under the Persist Dataset mount.
  while read -r unit _; do
    [[ "$unit" == *.mount ]] || continue
    what="$(systemctl show -P What "$unit")"
    [[ "$what" == "$IMPERMANENCE_MOUNT"/* ]] || continue
    fragment_path="$(systemctl show -P FragmentPath "$unit")"
    # Extensions and curated units both live in /usr/lib (ADR 0144); the
    # curated manifest tells them apart. A /persist fragment is a legacy
    # extension.
    case "$fragment_path" in
      /usr/lib/*)
        # The source path below the Persist Dataset mount is a curated one.
        if grep -qxF "${what:${#IMPERMANENCE_MOUNT}}" "$IMPERMANENCE_MANIFEST" \
             2>/dev/null; then label="curated"; else label="extension"; fi ;;
      "$IMPERMANENCE_MOUNT"/*) label="extension" ;;
      *)                       label="unknown" ;;
    esac
    echo "[$label] $unit"
  done < <(systemctl list-units --type=mount --no-legend --all)

  if [[ "$IMPERMANENCE_FILESYSTEM" == btrfs ]]; then
    impermanence_status_btrfs_blanks
  else
    impermanence_status_zfs_blanks
  fi
}

# impermanence_status_zfs_blanks — each Rollback Dataset's @blank and its drift.
impermanence_status_zfs_blanks() {
  local entry suffix dataset count missing=0
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    # The dataset suffix before the ":".
    suffix="$(printf '%s\n' "$entry" | cut -d: -f1)"
    dataset="$IMPERMANENCE_RPOOL/ROOT/$suffix"
    if ! zfs list -t snapshot "$dataset@blank" >/dev/null 2>&1; then
      echo "ERROR: $dataset@blank is missing — Rollback Hook will fail" \
        "closed on boot" >&2
      missing=1
      continue
    fi
    # How many paths changed since @blank.
    count="$(zfs diff "$dataset@blank" "$dataset" 2>/dev/null | wc -l)"
    echo "$dataset: $count paths changed since @blank" \
      "(run: zfs diff $dataset@blank $dataset)"
  done
  (( missing == 0 ))
}

# impermanence_status_btrfs_blanks — each rollback subvolume's @<name>@blank
# (ADR 0044); btrfs has no cheap per-path diff, so presence only.
impermanence_status_btrfs_blanks() {
  local entry suffix snapshot subvolumes="" path missing=0
  local -a fields
  # Each subvolume's path (the line's last field), "<FS_TREE>/" dropped.
  while read -ra fields; do
    ((${#fields[@]})) || continue
    path="${fields[-1]}"
    [[ "$path" == "<FS_TREE>/"* ]] && path="${path:10}"
    subvolumes+="${path}"$'\n'
  done < <(btrfs subvolume list -a "${IMPERMANENCE_ROOT:-/}" 2>/dev/null)
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    # The dataset suffix before the ":".
    suffix="$(printf '%s\n' "$entry" | cut -d: -f1)"
    snapshot="@${suffix}@blank"
    if ! printf '%s' "$subvolumes" | grep -qxF "$snapshot"; then
      echo "ERROR: $snapshot is missing — Rollback Hook will fail closed" \
        "on boot" >&2
      missing=1
      continue
    fi
    echo "$snapshot: present"
  done
  (( missing == 0 ))
}

curated_kind() {
  local target="$1" curated_file
  for curated_file in "${CURATED_FILES[@]}"; do
    [[ "$curated_file" == "$target" ]] && { echo f; return; }
  done
  echo d
}

apply_defaults_add_one() {
  local target="$1"
  local source_path="${IMPERMANENCE_ROOT}$target"
  local persist_path="$IMPERMANENCE_MOUNT$target"
  if [[ ! -e "$source_path" && ! -e "$persist_path" ]]; then
    echo "warning: skip missing curated source: $target" >&2
    return 0
  fi
  if [[ -e "$source_path" && ! -e "$persist_path" ]]; then
    mkdir -p "$(dirname "$persist_path")"
    cp -a "$source_path" "$persist_path"
  fi
  impermanence_common_persist_unapply "$target"
  impermanence_common_write_mount_unit "$target" \
    "${IMPERMANENCE_ROOT}/usr/lib/systemd/system"
  impermanence_common_link_wants "$target" \
    "${IMPERMANENCE_ROOT}/usr/lib/systemd/system/local-fs.target.wants"
}

rewrite_curated_tmpfiles() {
  local tmpfiles_directory="${IMPERMANENCE_ROOT}/usr/lib/tmpfiles.d"
  local tmpfiles_file="$tmpfiles_directory/impermanence-curated.conf"
  mkdir -p "$tmpfiles_directory"
  : > "$tmpfiles_file"
  local directory file
  for directory in "${CURATED_DIRS[@]}"; do
    printf "d %s 0755 root root - -\n" "$directory" >> "$tmpfiles_file"
  done
  for file in "${CURATED_FILES[@]}"; do
    printf "f %s 0644 root root - -\n" "$file" >> "$tmpfiles_file"
  done
}

apply_defaults_remove_one() {
  local target="$1"
  local escaped_path; escaped_path="$(systemd-escape --path "$target")"
  local unit_directory="${IMPERMANENCE_ROOT}/usr/lib/systemd/system"
  local unit="$unit_directory/$escaped_path.mount"
  local wants="$unit_directory/local-fs.target.wants/$escaped_path.mount"
  systemctl stop "$escaped_path.mount" 2>/dev/null || true
  rm -f "$unit" "$wants"
  local persist_path="$IMPERMANENCE_MOUNT$target"
  if [[ -e "$persist_path" ]]; then
    echo "removed curated default: $target (data preserved at" \
      "$persist_path — delete manually if not needed)"
  else
    echo "removed curated default: $target"
  fi
}

warn_kind_mismatch() {
  local target persist_path actual
  for target in "${CURATED_FILES[@]}"; do
    persist_path="$IMPERMANENCE_MOUNT$target"
    [[ -e "$persist_path" ]] || continue
    [[ -d "$persist_path" ]] && actual=d || actual=f
    if [[ "$actual" != f ]]; then
      echo "warning: $target persisted as directory but curated kind is" \
        "file; manual migration of $persist_path may be required" >&2
    fi
  done
  for target in "${CURATED_DIRS[@]}"; do
    persist_path="$IMPERMANENCE_MOUNT$target"
    [[ -e "$persist_path" ]] || continue
    [[ -d "$persist_path" ]] && actual=d || actual=f
    if [[ "$actual" != d ]]; then
      echo "warning: $target persisted as file but curated kind is" \
        "directory; manual migration of $persist_path may be required" >&2
    fi
  done
}

rewrite_manifest() {
  mkdir -p "$(dirname "$IMPERMANENCE_MANIFEST")"
  printf '%s\n' "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}" \
    | sort > "$IMPERMANENCE_MANIFEST"
}

impermanence_apply_defaults() {
  require_enabled
  local current previous="" added removed target
  current="$(printf '%s\n' "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}" | sort)"
  [[ -f "$IMPERMANENCE_MANIFEST" ]] \
    && previous="$(sort "$IMPERMANENCE_MANIFEST")"
  added="$(only_in_first "$current" "$previous")"
  removed="$(only_in_first "$previous" "$current")"
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    apply_defaults_add_one "$target"
  done < <(printf '%s\n' "$added")
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    apply_defaults_remove_one "$target"
  done < <(printf '%s\n' "$removed")
  rewrite_curated_tmpfiles
  rewrite_manifest
  warn_kind_mismatch
}

# only_in_first <lines> <lines> — the lines of the first sorted list absent
# from the second, in order.
only_in_first() {
  comm -23 <(printf '%s\n' "$1") <(printf '%s\n' "$2")
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi
  local verb="$1"; shift
  case "$verb" in
    add)    impermanence_add "$@" ;;
    remove) impermanence_remove "$@" ;;
    status) impermanence_status "$@" ;;
    apply-defaults) impermanence_apply_defaults "$@" ;;
    *)      usage; exit 2 ;;
  esac
}

main "$@"
