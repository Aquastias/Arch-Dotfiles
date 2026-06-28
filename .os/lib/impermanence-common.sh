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

# Rollback Datasets — dataset suffix → mountpoint.
# shellcheck disable=SC2034 # consumed by chroot/impermanence.sh, validation.sh,
# tools/impermanence.sh
ROLLBACK_DATASETS=(
  "etc:/etc"
  "root:/root"
  "opt:/opt"
  "srv:/srv"
  "usrlocal:/usr/local"
)

# Create the Persist Dataset EARLY (with the Rollback Datasets, before the OS is
# installed) so it lands in the zfs-list.cache and mounts at boot BEFORE
# local-fs.target. The curated Persist Mounts (RequiredBy=local-fs.target) then
# restore /etc/machine-id, host keys, the SOPS age key, etc. over the
# @blank-rolled-back /etc before early services run — dbus-broker hard-fails
# (restart-loops) on an empty /etc/machine-id, so this ordering is load-bearing.
# Idempotent.
imp_create_persist_dataset() {
  local dataset="$1" mount="$2"
  zfs list -H -o name "$dataset" >/dev/null 2>&1 && return 0
  zfs create -o mountpoint="$mount" -o canmount=on "$dataset"
}

# Create the Rollback Datasets EARLY — during pool/dataset creation, before the
# OS is installed — so pacstrap writes /etc, /root, /opt, /srv, /usr/local onto
# them AND they land in the zfs-list.cache (built later in chroot configure),
# letting zfs-mount-generator mount them at boot. canmount=on is REQUIRED:
# `zfs mount -a` and the generator's auto-mount both SKIP canmount=noauto, so a
# noauto dataset never mounts, /etc stays on the root dataset, and the @blank
# rollback becomes a no-op. Creating them late (post-pacstrap) is not an option
# — an empty dataset would mount over the already-populated path. Idempotent:
# pre-existing datasets are left untouched.
imp_create_rollback_datasets() {
  local rpool="$1"
  local entry suffix mp ds
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    mp="${entry#*:}"
    ds="$rpool/ROOT/$suffix"
    zfs list -H -o name "$ds" >/dev/null 2>&1 && continue
    zfs create -o mountpoint="$mp" -o canmount=on "$ds"
  done
}

# Write a bind-mount .mount unit at $units/<esc>.mount. systemd requires a
# .mount unit be named after its Where= (the escaped mount-point path); any
# other name loads as bad-setting and never mounts, so the unit MUST be
# <esc>.mount, not persist-<esc>.mount.
# $units defaults to the curated location under ${ROOT:-}/usr/lib/systemd/system.
# Caller must export IMPERMANENCE_MOUNT.
imp_write_mount_unit() {
  local target="$1"
  local units="${2:-${ROOT:-}/usr/lib/systemd/system}"
  local esc unit
  esc="$(systemd-escape --path "$target")"
  unit="$units/$esc.mount"
  mkdir -p "$units"
  cat > "$unit" <<UNIT
[Unit]
Description=Bind-mount persist over $target
# Order AFTER the ZFS datasets are mounted (zfs-mount.service = \`zfs mount -a\`):
# the source is on the Persist Dataset, the target on a Rollback Dataset. Do NOT
# order After=systemd-tmpfiles-setup.service — that service is itself
# After=local-fs.target, so with our Before=local-fs.target it forms an ordering
# cycle that systemd breaks by DROPPING this unit (it never mounts at boot). The
# mount auto-creates its own target directory, so tmpfiles is not needed here.
After=zfs-mount.service
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

# Symlink <esc>.mount under $wants/. $wants defaults to the curated
# local-fs.target.wants alongside the curated unit dir.
imp_link_wants() {
  local target="$1"
  local wants="${2:-${ROOT:-}/usr/lib/systemd/system/local-fs.target.wants}"
  local esc
  esc="$(systemd-escape --path "$target")"
  mkdir -p "$wants"
  ln -sf "../$esc.mount" "$wants/$esc.mount"
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
  systemctl start "$esc.mount"
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
  unit="$IMPERMANENCE_MOUNT/etc/systemd/system/$esc.mount"
  if [[ -f "$unit" ]]; then
    systemctl stop "$esc.mount"
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
#
# When $target is itself a mountpoint (e.g. /root, which is both a Rollback
# Dataset and a Curated Persist Default), the mountpoint directory can't be
# mv'd (EBUSY "Device or resource busy"). Move its CONTENTS instead and leave
# the now-empty mountpoint for the @blank snapshot + bind mount to cover.
persist_stage_in_move() {
  local target="$1"
  local live_root="${2:-${IMPERMANENCE_ROOT:-}}"
  local persist_root="${3:-$IMPERMANENCE_MOUNT}"
  local src="$live_root$target"
  local dst="$persist_root$target"
  [[ -e "$src" ]] || return 0
  if mountpoint -q "$src" 2>/dev/null; then
    mkdir -p "$dst"
    (
      shopt -s dotglob nullglob
      local entries=("$src"/*)
      ((${#entries[@]})) && mv -- "${entries[@]}" "$dst"/
    )
  else
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst"
  fi
}
