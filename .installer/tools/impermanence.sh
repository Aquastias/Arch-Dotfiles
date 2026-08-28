#!/usr/bin/env bash
# tools/impermanence.sh — operator CLI for Persist Extensions.
#
# Verbs: add <path>, remove [--yes] <path>.
# Host config is the source of truth; the tool edits jsonc first, then
# materializes mount unit + tmpfiles + data move to match.
#
# Env overrides (for testing):
#   IMPERMANENCE_ROOT       default empty; prefixes live-fs paths
#   IMPERMANENCE_MOUNT      default /persist
#   IMPERMANENCE_MANIFEST   default /usr/lib/impermanence/defaults.manifest
#   IMPERMANENCE_HOSTNAME   default $(hostname)
#   IMPERMANENCE_HOSTS_DIR  default <repo>/.os/hosts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../lib/jsonc.sh
source "$OS_DIR/lib/jsonc.sh"
# shellcheck source=../lib/impermanence-common.sh
source "$OS_DIR/lib/impermanence-common.sh"

: "${IMPERMANENCE_ROOT:=}"
: "${IMPERMANENCE_MOUNT:=/persist}"
: "${IMPERMANENCE_MANIFEST:=/usr/lib/impermanence/defaults.manifest}"
: "${IMPERMANENCE_HOSTNAME:=$(hostname)}"
: "${IMPERMANENCE_HOSTS_DIR:=$OS_DIR/hosts}"
: "${IMPERMANENCE_RPOOL:=rpool}"

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
  local target="$1" esc
  esc="$(systemd-escape --path "$target")"
  echo "$IMPERMANENCE_MOUNT/etc/systemd/system/$esc.mount"
}

# The host's unified profile.jsonc — persist paths live under .persist.*
# (the same schema the legacy config.jsonc carried, ADR 0036).
host_profile_file() {
  echo "$IMPERMANENCE_HOSTS_DIR/$IMPERMANENCE_HOSTNAME/profile.jsonc"
}

declare_in_host_profile() {
  local target="$1" kind="$2" cfg sel
  cfg="$(host_profile_file)"
  [[ -f "$cfg" ]] || return 0
  [[ "$kind" == d ]] && sel='.persist.directories' || sel='.persist.files'
  jsonc_append_to_array "$cfg" "$sel" "$target"
}

undeclare_in_host_profile() {
  local target="$1" cfg
  cfg="$(host_profile_file)"
  [[ -f "$cfg" ]] || return 0
  jsonc_remove_from_array "$cfg" '.persist.files' "$target"
  jsonc_remove_from_array "$cfg" '.persist.directories' "$target"
}

cmd_add() {
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
  unit="$(unit_path "$target")"
  if [[ -f "$unit" ]]; then
    echo "impermanence: '$target' is already persisted; no-op"
    return 0
  fi
  kind="$(path_kind "$target")"
  declare_in_host_profile "$target" "$kind"
  if ! (
    persist_stage_in_copy "$target" &&
    persist_apply "$target" "$kind" &&
    persist_activate "$target"
  ); then
    persist_unapply "$target"
    rm -rf "$IMPERMANENCE_MOUNT$target"
    undeclare_in_host_profile "$target"
    return 1
  fi
}

cmd_remove() {
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
  local unit; unit="$(unit_path "$target")"
  if [[ ! -f "$unit" ]]; then
    echo "impermanence: '$target' is not persisted; no-op"
    return 0
  fi
  persist_unapply "$target"
  undeclare_in_host_profile "$target"
  if (( move_back )); then
    persist_restore_data "$target"
  fi
}

cmd_status() {
  require_enabled
  local line unit what fp label
  # Persist Mounts are named <esc>.mount (systemd's .mount naming contract), so
  # they share no name prefix to glob. Identify them by their intrinsic marker:
  # a bind whose source (What=) lives under the Persist Dataset mount.
  while read -r line; do
    [[ -z "$line" ]] && continue
    unit="${line%% *}"
    [[ "$unit" == *.mount ]] || continue
    what="$(systemctl show -p What --value "$unit")"
    [[ "$what" == "$IMPERMANENCE_MOUNT"/* ]] || continue
    fp="$(systemctl show -p FragmentPath --value "$unit")"
    case "$fp" in
      /usr/lib/*)              label="curated" ;;
      "$IMPERMANENCE_MOUNT"/*) label="extension" ;;
      *)                       label="unknown" ;;
    esac
    echo "[$label] $unit"
  done < <(systemctl list-units --type=mount --no-legend --all)

  local entry suffix ds count missing=0
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    ds="$IMPERMANENCE_RPOOL/ROOT/$suffix"
    if ! zfs list -t snapshot "$ds@blank" >/dev/null 2>&1; then
      echo "ERROR: $ds@blank is missing — Rollback Hook will fail closed on boot" >&2
      missing=1
      continue
    fi
    count="$(zfs diff "$ds@blank" "$ds" 2>/dev/null | wc -l)"
    echo "$ds: $count paths changed since @blank (run: zfs diff $ds@blank $ds)"
  done
  (( missing == 0 ))
}

curated_kind() {
  local target="$1" p
  for p in "${CURATED_FILES[@]}"; do
    [[ "$p" == "$target" ]] && { echo f; return; }
  done
  echo d
}

apply_defaults_add_one() {
  local target="$1"
  local src="${IMPERMANENCE_ROOT}$target"
  local dst="$IMPERMANENCE_MOUNT$target"
  if [[ ! -e "$src" && ! -e "$dst" ]]; then
    echo "warning: skip missing curated source: $target" >&2
    return 0
  fi
  if [[ -e "$src" && ! -e "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
  persist_unapply "$target"
  imp_write_mount_unit "$target" \
    "${IMPERMANENCE_ROOT}/usr/lib/systemd/system"
  imp_link_wants "$target" \
    "${IMPERMANENCE_ROOT}/usr/lib/systemd/system/local-fs.target.wants"
}

rewrite_curated_tmpfiles() {
  local dir="${IMPERMANENCE_ROOT}/usr/lib/tmpfiles.d"
  local f="$dir/impermanence-curated.conf"
  mkdir -p "$dir"
  : > "$f"
  local d file
  for d in "${CURATED_DIRS[@]}"; do
    printf "d %s 0755 root root - -\n" "$d" >> "$f"
  done
  for file in "${CURATED_FILES[@]}"; do
    printf "f %s 0644 root root - -\n" "$file" >> "$f"
  done
}

apply_defaults_remove_one() {
  local target="$1"
  local esc; esc="$(systemd-escape --path "$target")"
  local unit_dir="${IMPERMANENCE_ROOT}/usr/lib/systemd/system"
  local unit="$unit_dir/$esc.mount"
  local wants="$unit_dir/local-fs.target.wants/$esc.mount"
  systemctl stop "$esc.mount" 2>/dev/null || true
  rm -f "$unit" "$wants"
  local dst="$IMPERMANENCE_MOUNT$target"
  if [[ -e "$dst" ]]; then
    echo "removed curated default: $target (data preserved at $dst — delete manually if not needed)"
  else
    echo "removed curated default: $target"
  fi
}

warn_kind_mismatch() {
  local target dst actual
  for target in "${CURATED_FILES[@]}"; do
    dst="$IMPERMANENCE_MOUNT$target"
    [[ -e "$dst" ]] || continue
    [[ -d "$dst" ]] && actual=d || actual=f
    if [[ "$actual" != f ]]; then
      echo "warning: $target persisted as directory but curated kind is file; manual migration of $dst may be required" >&2
    fi
  done
  for target in "${CURATED_DIRS[@]}"; do
    dst="$IMPERMANENCE_MOUNT$target"
    [[ -e "$dst" ]] || continue
    [[ -d "$dst" ]] && actual=d || actual=f
    if [[ "$actual" != d ]]; then
      echo "warning: $target persisted as file but curated kind is directory; manual migration of $dst may be required" >&2
    fi
  done
}

rewrite_manifest() {
  local dir; dir="$(dirname "$IMPERMANENCE_MANIFEST")"
  mkdir -p "$dir"
  printf '%s\n' "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}" \
    | sort > "$IMPERMANENCE_MANIFEST"
}

cmd_apply_defaults() {
  require_enabled
  local cur prev added target
  cur="$(mktemp)"
  prev="$(mktemp)"
  printf '%s\n' "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}" | sort > "$cur"
  if [[ -f "$IMPERMANENCE_MANIFEST" ]]; then
    sort "$IMPERMANENCE_MANIFEST" > "$prev"
  else
    : > "$prev"
  fi
  added="$(comm -23 "$cur" "$prev")"
  local removed
  removed="$(comm -13 "$cur" "$prev")"
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    apply_defaults_add_one "$target"
  done <<< "$added"
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    apply_defaults_remove_one "$target"
  done <<< "$removed"
  rewrite_curated_tmpfiles
  rewrite_manifest
  warn_kind_mismatch
  rm -f "$cur" "$prev"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi
  local verb="$1"; shift
  case "$verb" in
    add)    cmd_add "$@" ;;
    remove) cmd_remove "$@" ;;
    status) cmd_status "$@" ;;
    apply-defaults) cmd_apply_defaults "$@" ;;
    *)      usage; exit 2 ;;
  esac
}

main "$@"
