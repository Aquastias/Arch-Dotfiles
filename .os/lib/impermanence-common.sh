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
  local units="${3:-$IMPERMANENCE_MOUNT/etc/systemd/system}"
  local conf="${4:-$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf}"
  imp_write_mount_unit "$target" "$units"
  local mode entry
  mkdir -p "$(dirname "$conf")"
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

# Tear down the Persist Mount for $target: stop the unit, remove the unit
# file, remove the tmpfiles entry, daemon-reload. No data movement; pair
# with persist_restore_data when the runtime caller wants `--yes` semantics.
# Idempotent: no-op when the unit file is absent.
persist_unapply() {
  local target="$1" esc unit conf tmp
  esc="$(systemd-escape --path "$target")"
  unit="$IMPERMANENCE_MOUNT/etc/systemd/system/persist-$esc.mount"
  if [[ -f "$unit" ]]; then
    systemctl stop "persist-$esc.mount"
    rm -f "$unit"
    systemctl daemon-reload
  fi
  conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  if [[ -f "$conf" ]]; then
    tmp="$(mktemp)"
    awk -v t="$target" '
      {
        if ($0 ~ "^[df] " t " ") next
        print
      }
    ' "$conf" > "$tmp"
    mv "$tmp" "$conf"
  fi
}

# Move data at $IMPERMANENCE_MOUNT$target back to ${IMPERMANENCE_ROOT}$target.
# Used by runtime `remove --yes`. Missing source is a warned no-op so the
# operator can recover from partial state without an error.
persist_restore_data() {
  local target="$1"
  local src="$IMPERMANENCE_MOUNT$target"
  local dst="${IMPERMANENCE_ROOT}$target"
  if [[ ! -e "$src" ]]; then
    echo "warning: no persisted data at $src; nothing to move back" >&2
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  rm -rf "$dst"
  mv "$src" "$dst"
}

# Move live data at $target to the Persist Dataset (mv). Install-time only:
# the rolled-back dataset will lose any live copy on next boot anyway, so
# the move is safe and avoids leaving a duplicate. Missing source is a
# no-op (curated lists include paths not present on every host).
persist_stage_in_move() {
  local target="$1"
  local live_root="${2:-${IMPERMANENCE_ROOT:-}}"
  local persist_root="${3:-$IMPERMANENCE_MOUNT}"
  local src="$live_root$target"
  local dst="$persist_root$target"
  [[ -e "$src" ]] || return 0
  mkdir -p "$(dirname "$dst")"
  mv "$src" "$dst"
}
