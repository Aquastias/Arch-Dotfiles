#!/usr/bin/env bash
# lib/chroot/impermanence.sh — Chroot Configuration Module for impermanence.
# Creates Persist + Rollback Datasets, generates bootstrap + curated mount
# units, takes @blank snapshots. No-op when IMPERMANENCE_ENABLED!=true.
#
# All file writes are rooted at ${ROOT:-} so tests can redirect under a
# temp dir. Production callers leave ROOT unset (writes to / inside chroot).

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

_impermanence_dataset_exists() {
  zfs list -H -o name "$1" >/dev/null 2>&1
}

_impermanence_create_persist_dataset() {
  if _impermanence_dataset_exists "$IMPERMANENCE_DATASET"; then
    info "impermanence: $IMPERMANENCE_DATASET already exists, skipping create"
    return 0
  fi
  zfs create \
    -o mountpoint="$IMPERMANENCE_MOUNT" \
    -o canmount=on \
    "$IMPERMANENCE_DATASET"
}

_impermanence_create_rollback_datasets() {
  local entry suffix mp ds
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    mp="${entry#*:}"
    ds="$RPOOL/ROOT/$suffix"
    if _impermanence_dataset_exists "$ds"; then
      info "impermanence: $ds already exists, skipping create"
      continue
    fi
    zfs create \
      -o mountpoint="$mp" \
      -o canmount=noauto \
      "$ds"
  done
}

_impermanence_write_manifest() {
  local dir="${ROOT:-}/usr/lib/impermanence"
  mkdir -p "$dir"
  printf '%s\n' "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}" \
    | sort > "$dir/defaults.manifest"
}

# Write one bind-mount .mount unit. Caller passes target path (e.g. /etc/x).
_impermanence_write_mount_unit() {
  local target="$1"
  local units="${ROOT:-}/usr/lib/systemd/system"
  local esc unit
  esc="$(systemd-escape --path "$target")"
  unit="$units/$esc.mount"
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

_impermanence_link_wants() {
  local target="$1"
  local wants="${ROOT:-}/usr/lib/systemd/system/local-fs.target.wants"
  local esc
  esc="$(systemd-escape --path "$target")"
  mkdir -p "$wants"
  ln -sf "../$esc.mount" "$wants/$esc.mount"
}

_impermanence_write_curated_units() {
  local p
  for p in "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}"; do
    _impermanence_write_mount_unit "$p"
    _impermanence_link_wants "$p"
  done
}

_impermanence_write_curated_tmpfiles() {
  local dir="${ROOT:-}/usr/lib/tmpfiles.d"
  local f="$dir/impermanence-curated.conf"
  local d file
  mkdir -p "$dir"
  : > "$f"
  for d in "${CURATED_DIRS[@]}"; do
    printf "d %s 0755 root root - -\n" "$d" >> "$f"
  done
  for file in "${CURATED_FILES[@]}"; do
    printf "f %s 0644 root root - -\n" "$file" >> "$f"
  done
}

_impermanence_write_bootstrap() {
  local dir="${ROOT:-}/usr/lib/tmpfiles.d"
  local f="$dir/impermanence-bootstrap.conf"
  local p
  mkdir -p "$dir"
  : > "$f"
  for p in /etc/systemd/system /etc/tmpfiles.d; do
    printf "d %s 0755 root root - -\n" "$p" >> "$f"
    _impermanence_write_mount_unit "$p"
    _impermanence_link_wants "$p"
  done
}

_impermanence_move_curated() {
  local p src dst
  for p in "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}"; do
    src="${ROOT:-}$p"
    dst="${ROOT:-}${IMPERMANENCE_MOUNT}$p"
    if [[ ! -e "$src" ]]; then
      info "impermanence: skip missing curated source $p"
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst"
  done
}

_impermanence_snapshot_blank() {
  local entry suffix
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    zfs snapshot "$RPOOL/ROOT/$suffix@blank"
  done
}

_impermanence_write_rollback_hook() {
  local idir="${ROOT:-}/usr/lib/initcpio/install"
  local hdir="${ROOT:-}/usr/lib/initcpio/hooks"
  mkdir -p "$idir" "$hdir"

  cat > "$idir/zfs-rollback" <<'INSTALL'
#!/bin/bash
build() {
  add_runscript
}
help() {
  cat <<HELP
Rolls back curated ZFS datasets to @blank on every boot. Fails closed
to an emergency shell if any @blank snapshot is missing.
HELP
}
INSTALL

  # Bake the dataset list into the runtime hook (no kernel cmdline lookup).
  local entry suffix ds_list=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    ds_list+="$RPOOL/ROOT/$suffix "
  done
  ds_list="${ds_list% }"

  cat > "$hdir/zfs-rollback" <<HOOK
#!/usr/bin/ash
run_hook() {
  local datasets="$ds_list"
  local ds
  for ds in \$datasets; do
    if ! zfs list -t snapshot "\${ds}@blank" >/dev/null 2>&1; then
      err "impermanence: @blank snapshot missing for \${ds}"
      launch_interactive_shell
    fi
    zfs rollback -r "\${ds}@blank"
  done
}
HOOK
}

impermanence_apply() {
  [[ "${IMPERMANENCE_ENABLED:-false}" == "true" ]] || return 0
  _impermanence_create_persist_dataset
  _impermanence_create_rollback_datasets
  _impermanence_write_manifest
  _impermanence_write_curated_units
  _impermanence_write_curated_tmpfiles
  _impermanence_write_bootstrap
  _impermanence_write_rollback_hook
  _impermanence_move_curated
  _impermanence_snapshot_blank
}

# When invoked as a script (not sourced), load state and apply.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=./load-state.sh
  source "$(dirname "${BASH_SOURCE[0]}")/load-state.sh"
  set -Eeuo pipefail
  trap 'echo "[chroot:impermanence] failed at line $LINENO" >&2' ERR
  impermanence_apply
fi
