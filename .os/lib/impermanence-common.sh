#!/usr/bin/env bash
# lib/impermanence-common.sh — shared between the Chroot Configuration Module
# (install-time) and the Impermanence Tool (runtime). Holds Curated Persist
# Defaults + the unit/wants writers both consumers need. Sourced only.

# ── Curated Persist Defaults — single source of truth ───────────────────────
CURATED_FILES=(
  /etc/machine-id
  /etc/hostname
  /etc/locale.conf
  /etc/vconsole.conf
  /etc/adjtime
  /etc/fstab
)
CURATED_DIRS=(
  /etc/ssh
  /etc/secrets
  /etc/NetworkManager/system-connections
  /etc/sudoers.d
  /etc/pacman.d
  /root
)

# Rollback Datasets — dataset suffix → mountpoint.
ROLLBACK_DATASETS=(
  "etc:/etc"
  "root:/root"
  "opt:/opt"
  "srv:/srv"
  "usrlocal:/usr/local"
)

# Write a bind-mount .mount unit at $units/persist-<esc>.mount.
# $units defaults to the curated location under ${ROOT:-}/usr/lib/systemd/system.
# Caller must export IMPERMANENCE_MOUNT.
imp_write_mount_unit() {
  local target="$1"
  local units="${2:-${ROOT:-}/usr/lib/systemd/system}"
  local esc unit
  esc="$(systemd-escape --path "$target")"
  unit="$units/persist-$esc.mount"
  mkdir -p "$units"
  cat > "$unit" <<UNIT
[Unit]
Description=Bind-mount persist over $target
After=systemd-tmpfiles-setup.service
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

# Symlink persist-<esc>.mount under $wants/. $wants defaults to the curated
# local-fs.target.wants alongside the curated unit dir.
imp_link_wants() {
  local target="$1"
  local wants="${2:-${ROOT:-}/usr/lib/systemd/system/local-fs.target.wants}"
  local esc
  esc="$(systemd-escape --path "$target")"
  mkdir -p "$wants"
  ln -sf "../persist-$esc.mount" "$wants/persist-$esc.mount"
}
