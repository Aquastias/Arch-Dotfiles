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

# ── Persist Mount verbs (orchestrators) ─────────────────────────────────────

# Write the Persist Mount unit for $target. No reload, no start — pair with
# persist_activate when the running system should pick the unit up
# immediately (runtime). Install-time callers skip persist_activate because
# the system is not running.
persist_apply() {
  local target="$1" kind="$2"
  local units="$IMPERMANENCE_MOUNT/etc/systemd/system"
  imp_write_mount_unit "$target" "$units"
  local dir="$IMPERMANENCE_MOUNT/etc/tmpfiles.d"
  local conf="$dir/impermanence-extensions.conf"
  local mode entry
  mkdir -p "$dir"
  [[ "$kind" == d ]] && mode=0755 || mode=0644
  entry="$(printf "%s %s %s root root - -" "$kind" "$target" "$mode")"
  if [[ ! -f "$conf" ]] || ! grep -qxF "$entry" "$conf"; then
    printf "%s\n" "$entry" >> "$conf"
  fi
}

# Reload systemd and start the Persist Mount for $target. Pairs with
# persist_apply; install-time callers skip this because the system is not
# running yet.
persist_activate() {
  local target="$1" esc
  esc="$(systemd-escape --path "$target")"
  systemctl daemon-reload
  systemctl start "persist-$esc.mount"
}

# ── Persist data-staging helpers ────────────────────────────────────────────

# Copy live data at $target into the Persist Dataset (cp -a). Runtime-only:
# the bind mount activates immediately and the original must remain visible
# until the Persist Mount covers it.
persist_stage_in_copy() {
  local target="$1"
  local src="${IMPERMANENCE_ROOT}$target"
  local dst="$IMPERMANENCE_MOUNT$target"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
}
