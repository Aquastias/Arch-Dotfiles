#!/usr/bin/env bash
# lib/impermanence-common.sh — shared between the Chroot Configuration Module
# (install-time) and the Impermanence Tool (runtime). Holds Curated Persist
# Defaults + the unit/wants writers both consumers need. Sourced only.

# ── Curated Persist Defaults — single source of truth ───────────────────────
# shellcheck disable=SC2034 # consumed by chroot/impermanence.sh, validation.sh,
# tools/impermanence.sh
CURATED_FILES=(
  /etc/machine-id
  /etc/hostname
  /etc/locale.conf
  /etc/vconsole.conf
  /etc/adjtime
  /etc/fstab
)
# shellcheck disable=SC2034 # consumed by chroot/impermanence.sh, validation.sh,
# tools/impermanence.sh
CURATED_DIRS=(
  /etc/ssh
  /etc/secrets             # sops age key lives here
  /etc/cryptsetup-keys.d   # data-group LUKS/zfs keyfiles (ADR 0043)
  /etc/NetworkManager/system-connections
  /etc/sudoers.d
  /etc/pacman.d
  /root
)

# Rollback Datasets — dataset suffix → mountpoint. No /root: it is a Curated
# Persist Default, and a bind over a rolled-back /root shares root.mount with
# the dataset's own mount unit and loses (ADR 0144).
# shellcheck disable=SC2034 # consumed by chroot/impermanence.sh, validation.sh,
# tools/impermanence.sh
ROLLBACK_DATASETS=(
  "etc:/etc"
  "opt:/opt"
  "srv:/srv"
  "usrlocal:/usr/local"
)

# The btrfs mirror of the Rollback Datasets (ADR 0044). Same curated path list
# (ROLLBACK_DATASETS, the single source of truth), emitted as `@<suffix>
# <mountpoint>` so the btrfs subvol layout can't drift from the zfs one on which
# paths roll back. The btrfs adapter folds these into its create/mount/fstab
# loops when impermanence is enabled; the `@blank` snapshot + boot rollback hook
# operate on the same names. Pure: string emitter, no disk access.
impermanence_common_btrfs_rollback_subvolumes() {
  local entry suffix mountpoint
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    mountpoint="${entry#*:}"
    printf '@%s %s\n' "$suffix" "$mountpoint"
  done
}

# Create the Persist Dataset EARLY (before the OS) so it lands in zfs-list.cache
# and mounts BEFORE local-fs.target. The Persist Mounts then restore
# /etc/machine-id, host keys, the SOPS age key, etc. over the @blank-rolled-back
# /etc before early services run — dbus-broker restart-loops on an empty
# machine-id, so this ordering is load-bearing. Idempotent.
impermanence_common_create_persist_dataset() {
  local dataset="$1" mount="$2"
  zfs list -H -o name "$dataset" >/dev/null 2>&1 && return 0
  zfs create -o mountpoint="$mount" -o canmount=on "$dataset"
}

# Create the Rollback Datasets EARLY (before the OS) so pacstrap writes /etc,
# /opt, /srv, /usr/local onto them AND they land in zfs-list.cache for
# zfs-mount-generator. canmount=on is REQUIRED: `zfs mount -a` and the generator
# both SKIP canmount=noauto, so a noauto dataset never mounts and @blank rollback
# no-ops. Creating them late would mount an empty dataset over a populated path.
# Idempotent.
impermanence_common_create_rollback_datasets() {
  local rpool="$1"
  local entry suffix mountpoint dataset
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    mountpoint="${entry#*:}"
    dataset="$rpool/ROOT/$suffix"
    zfs list -H -o name "$dataset" >/dev/null 2>&1 && continue
    zfs create -o mountpoint="$mountpoint" -o canmount=on "$dataset"
  done
}

# The systemd unit a Persist Mount over $target must order After=, so the bind's
# source/target are mounted first (ADR 0044). zfs: the single zfs-mount.service
# (`zfs mount -a`). btrfs: each rollback subvol mounts via fstab as its own
# <escaped-path>.mount, so order After= the owning subvol's mount unit (longest
# rollback mountpoint that is a path-prefix of $target); a path on no rollback
# subvol lives on @ (root) → the root mount unit `-.mount`.
impermanence_common_mount_after_unit() {
  local target="$1"
  if [[ "${FILESYSTEM:-zfs}" != "btrfs" ]]; then
    printf 'zfs-mount.service\n'; return 0
  fi
  local entry mountpoint best=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    mountpoint="${entry#*:}"
    if [[ "$target" == "$mountpoint" || "$target" == "$mountpoint"/* ]]; then
      [[ ${#mountpoint} -gt ${#best} ]] && best="$mountpoint"
    fi
  done
  if [[ -z "$best" ]]; then
    printf -- '-.mount\n'
  else
    printf '%s.mount\n' "$(systemd-escape --path "$best")"
  fi
}

# Write a bind-mount .mount unit at $units/<escaped-path>.mount. systemd
# requires a .mount unit be named after its Where= (the escaped mount-point
# path); any other name loads as bad-setting and never mounts, so the unit MUST
# be <escaped-path>.mount, not persist-<escaped-path>.mount.
# $units defaults to the curated location under ${ROOT:-}/usr/lib/systemd/system.
# Caller must export IMPERMANENCE_MOUNT.
impermanence_common_write_mount_unit() {
  local target="$1"
  local units="${2:-${ROOT:-}/usr/lib/systemd/system}"
  local escaped_path unit after
  escaped_path="$(systemd-escape --path "$target")"
  unit="$units/$escaped_path.mount"
  after="$(impermanence_common_mount_after_unit "$target")"
  mkdir -p "$units"
  cat > "$unit" <<UNIT
[Unit]
Description=Bind-mount persist over $target
# Order AFTER the rollback container is mounted (zfs: zfs-mount.service =
# \`zfs mount -a\`; btrfs: the owning subvol's fstab <esc>.mount): the source is
# on the Persist storage, the target on a rollback container. Do NOT order
# After=systemd-tmpfiles-setup.service — that service is itself
# After=local-fs.target, so with our Before=local-fs.target it forms an ordering
# cycle that systemd breaks by DROPPING this unit (it never mounts at boot). The
# mount auto-creates its own target directory, so tmpfiles is not needed here.
After=$after
Before=local-fs.target

[Mount]
What=$IMPERMANENCE_MOUNT$target
Where=$target
Type=none
Options=bind

[Install]
RequiredBy=local-fs.target
UNIT
}

# Symlink <escaped-path>.mount under $wants/. $wants defaults to the curated
# local-fs.target.wants alongside the curated unit dir.
impermanence_common_link_wants() {
  local target="$1"
  local wants="${2:-${ROOT:-}/usr/lib/systemd/system/local-fs.target.wants}"
  local escaped_path
  escaped_path="$(systemd-escape --path "$target")"
  mkdir -p "$wants"
  ln -sf "../$escaped_path.mount" "$wants/$escaped_path.mount"
}

# _impermanence_common_make_parent <path> — create <path>'s parent directory
# (`mkdir -p "$(dirname <path>)"`; this file runs without a stdlib).
_impermanence_common_make_parent() {
  local path="$1" parent
  while [[ "$path" == */ && "$path" != / ]]; do path="${path%/}"; done
  parent="${path%/*}"
  [[ "$path" == */* ]] || parent="."
  mkdir -p "${parent:-/}"
}

# ── Persist Mount verbs (orchestrators) ─────────────────────────────────────

# Write the Persist Mount unit for $target. No reload, no start — pair with
# impermanence_common_persist_activate when the running system should pick the unit up
# immediately (runtime). Install-time callers skip impermanence_common_persist_activate because
# the system is not running.
# Units default to /usr/lib: PID 1 plans boot before the /etc/systemd/system
# bootstrap bind exists, so a unit (or wants link) only on /persist never
# mounts at boot (ADR 0144).
impermanence_common_persist_apply() {
  local target="$1" kind="$2"
  local units="${3:-${IMPERMANENCE_ROOT:-}/usr/lib/systemd/system}"
  local config_file="${4:-}"
  if [[ -z "$config_file" ]]; then
    config_file="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/"
    config_file+="impermanence-extensions.conf"
  fi
  impermanence_common_write_mount_unit "$target" "$units"
  local mode entry
  _impermanence_common_make_parent "$config_file"
  [[ "$kind" == d ]] && mode=0755 || mode=0644
  entry="$(printf "%s %s %s root root - -" "$kind" "$target" "$mode")"
  if [[ ! -f "$config_file" ]] || ! grep -qxF "$entry" "$config_file"; then
    printf "%s\n" "$entry" >> "$config_file"
  fi
}

# Reload systemd and start the Persist Mount for $target. Pairs with
# impermanence_common_persist_apply; install-time callers skip this because the system is not
# running yet.
impermanence_common_persist_activate() {
  local target="$1" escaped_path
  escaped_path="$(systemd-escape --path "$target")"
  systemctl daemon-reload
  systemctl start "$escaped_path.mount"
}

# ── Persist data-staging helpers ────────────────────────────────────────────

# Copy live data at $target into the Persist Dataset (cp -a). Runtime-only:
# the bind mount activates immediately and the original must remain visible
# until the Persist Mount covers it.
impermanence_common_persist_stage_in_copy() {
  local target="$1"
  local source_path="${IMPERMANENCE_ROOT}$target"
  local destination="$IMPERMANENCE_MOUNT$target"
  _impermanence_common_make_parent "$destination"
  cp -a "$source_path" "$destination"
}

# Tear down the Persist Mount for $target: stop the unit, remove the unit
# file, remove the tmpfiles entry, daemon-reload. No data movement; pair
# with impermanence_common_persist_restore_data when the runtime caller wants `--yes` semantics.
# Idempotent. Also clears a legacy unit + wants link under
# /persist/etc/systemd/system (pre-ADR 0144 extensions).
impermanence_common_persist_unapply() {
  local target="$1" escaped_path directory found=0 config_file temporary_file
  escaped_path="$(systemd-escape --path "$target")"
  for directory in "${IMPERMANENCE_ROOT:-}/usr/lib/systemd/system" \
             "$IMPERMANENCE_MOUNT/etc/systemd/system"; do
    rm -f "$directory/local-fs.target.wants/$escaped_path.mount"
    [[ -f "$directory/$escaped_path.mount" ]] || continue
    ((found)) || systemctl stop "$escaped_path.mount"
    rm -f "$directory/$escaped_path.mount"; found=1
  done
  ((found)) && systemctl daemon-reload
  config_file="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  if [[ -f "$config_file" ]]; then
    temporary_file="$(mktemp)"
    awk -v t="$target" '
      {
        if (($1 == "d" || $1 == "f") && $2 == t) next
        print
      }
    ' "$config_file" > "$temporary_file"
    mv "$temporary_file" "$config_file"
  fi
}

# Move data at $IMPERMANENCE_MOUNT$target back to ${IMPERMANENCE_ROOT}$target.
# Used by runtime `remove --yes`. Missing source is a warned no-op so the
# operator can recover from partial state without an error.
impermanence_common_persist_restore_data() {
  local target="$1"
  local source_path="$IMPERMANENCE_MOUNT$target"
  local destination="${IMPERMANENCE_ROOT}$target"
  if [[ ! -e "$source_path" ]]; then
    echo "warning: no persisted data at $source_path; nothing to move back" >&2
    return 0
  fi
  _impermanence_common_make_parent "$destination"
  rm -rf "$destination"
  mv "$source_path" "$destination"
}

# Move live data at $target to the Persist Dataset (mv). Install-time only:
# the rolled-back dataset will lose any live copy on next boot anyway, so
# the move is safe and avoids leaving a duplicate. Missing source is a
# no-op (curated lists include paths not present on every host).
#
# When $target is itself a mountpoint (a dataset/subvol mounted there), the
# mountpoint directory can't be mv'd (EBUSY "Device or resource busy"). Move
# its CONTENTS instead and leave the now-empty mountpoint for the bind to cover.
impermanence_common_persist_stage_in_move() {
  local target="$1"
  local live_root="${2:-${IMPERMANENCE_ROOT:-}}"
  local persist_root="${3:-$IMPERMANENCE_MOUNT}"
  local source_path="$live_root$target"
  local destination="$persist_root$target"
  [[ -e "$source_path" ]] || return 0
  if mountpoint -q "$source_path" 2>/dev/null; then
    mkdir -p "$destination"
    (
      shopt -s dotglob nullglob
      local entries=("$source_path"/*)
      if ((${#entries[@]})); then mv -- "${entries[@]}" "$destination"/; fi
    )
  else
    _impermanence_common_make_parent "$destination"
    mv "$source_path" "$destination"
  fi
}
