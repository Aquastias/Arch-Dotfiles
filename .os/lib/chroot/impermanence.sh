#!/usr/bin/env bash
# lib/chroot/impermanence.sh — Chroot Configuration Module for impermanence.
# Creates Persist + Rollback Datasets, generates bootstrap + curated mount
# units, takes @blank snapshots. No-op when IMPERMANENCE_ENABLED!=true.
#
# All file writes are rooted at ${ROOT:-} so tests can redirect under a
# temp dir. Production callers leave ROOT unset (writes to / inside chroot).

# Curated Persist Defaults + writers come from the shared common lib.
# Chroot stages it as sibling; source tree has it one level up.
# shellcheck source=../impermanence-common.sh
_IMP_DIR="$(dirname "${BASH_SOURCE[0]}")"
_IMP_COMMON="$_IMP_DIR/impermanence-common.sh"
[[ -f "$_IMP_COMMON" ]] || _IMP_COMMON="$_IMP_DIR/../impermanence-common.sh"
# shellcheck disable=SC1090
source "$_IMP_COMMON"

# Local logger — chroot scripts don't source lib/common.sh, and the unset
# `info` shadows by texinfo's /usr/bin/info, which fails under set -e.
info() { printf '[impermanence] %s\n' "$*" >&2; }

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

_impermanence_apply_curated() {
  local units="${ROOT:-}/usr/lib/systemd/system"
  local wants="$units/local-fs.target.wants"
  local conf="${ROOT:-}/usr/lib/tmpfiles.d/impermanence-curated.conf"
  mkdir -p "$(dirname "$conf")"
  : > "$conf"
  local target
  for target in "${CURATED_DIRS[@]}"; do
    persist_apply "$target" d "$units" "$conf"
    imp_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
    else
      info "impermanence: skip missing curated source $target"
    fi
  done
  for target in "${CURATED_FILES[@]}"; do
    persist_apply "$target" f "$units" "$conf"
    imp_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
    else
      info "impermanence: skip missing curated source $target"
    fi
  done
}

_impermanence_apply_extensions() {
  local units="${ROOT:-}${IMPERMANENCE_MOUNT}/etc/systemd/system"
  local wants="$units/local-fs.target.wants"
  local conf="${ROOT:-}${IMPERMANENCE_MOUNT}/etc/tmpfiles.d/impermanence-extensions.conf"
  mkdir -p "$(dirname "$conf")"
  : > "$conf"
  local target
  for target in "${PERSIST_DIRECTORIES[@]:-}"; do
    [[ -z "$target" ]] && continue
    persist_apply "$target" d "$units" "$conf"
    imp_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
    else
      info "impermanence: skip missing extension source $target"
    fi
  done
  for target in "${PERSIST_FILES[@]:-}"; do
    [[ -z "$target" ]] && continue
    persist_apply "$target" f "$units" "$conf"
    imp_link_wants "$target" "$wants"
    if [[ -e "${ROOT:-}$target" ]]; then
      persist_stage_in_move "$target" "${ROOT:-}" "${ROOT:-}${IMPERMANENCE_MOUNT}"
    else
      info "impermanence: skip missing extension source $target"
    fi
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
    imp_write_mount_unit "$p"
    imp_link_wants "$p"
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

  # Must be run_latehook: the archzfs zfs hook only imports the pool in
  # its own run_latehook, so during run_hook the pool isn't available and
  # `zfs list` fails. HOOKS= order still applies (zfs latehook → ours).
  cat > "$hdir/zfs-rollback" <<HOOK
#!/usr/bin/ash
run_latehook() {
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

_impermanence_write_resnapshot_helper() {
  local dir="${ROOT:-}/usr/lib/impermanence"
  local f="$dir/resnapshot.sh"
  local entry suffix ds_list=""
  for entry in "${ROLLBACK_DATASETS[@]}"; do
    suffix="${entry%%:*}"
    ds_list+="$RPOOL/ROOT/$suffix "
  done
  ds_list="${ds_list% }"
  mkdir -p "$dir"
  cat > "$f" <<HELPER
#!/usr/bin/env bash
# Re-snapshot @blank on every Rollback Dataset after a pacman transaction.
# Idempotent: a missing @blank (destroy error) is ignored; the snapshot
# command then creates it fresh. Errors are logged but never abort —
# pacman has already succeeded by the time this hook fires.
#
# v1 leak: this script runs PostTransaction only. User edits to non-
# persisted paths made before a pacman run get baked into the new @blank
# and survive one extra reboot. The fix is a pre-transaction strict-mode
# hook with 'os impermanence diff/accept-drift/revert-drift' verbs,
# deferred to v2.
datasets="$ds_list"
for ds in \$datasets; do
  if zfs destroy "\${ds}@blank" 2>/dev/null; then
    logger -t impermanence "destroyed \${ds}@blank"
  fi
  if zfs snapshot "\${ds}@blank"; then
    logger -t impermanence "snapshotted \${ds}@blank"
  else
    logger -t impermanence "FAILED snapshot \${ds}@blank"
  fi
done
HELPER
  chmod 0755 "$f"
}

_impermanence_write_resnapshot_hook() {
  local dir="${ROOT:-}/etc/pacman.d/hooks"
  mkdir -p "$dir"
  cat > "$dir/zz-impermanence-resnapshot.hook" <<'HOOK'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Operation = Remove
Target = *

[Action]
Description = Re-snapshotting @blank on Rollback Datasets...
When = PostTransaction
Exec = /usr/lib/impermanence/resnapshot.sh
HOOK
}

impermanence_apply() {
  [[ "${IMPERMANENCE_ENABLED:-false}" == "true" ]] || return 0
  local step
  for step in \
    _impermanence_create_persist_dataset \
    _impermanence_create_rollback_datasets \
    _impermanence_write_manifest \
    _impermanence_apply_curated \
    _impermanence_write_bootstrap \
    _impermanence_apply_extensions \
    _impermanence_write_rollback_hook \
    _impermanence_write_resnapshot_hook \
    _impermanence_write_resnapshot_helper \
    _impermanence_snapshot_blank
  do
    info "step: $step"
    "$step"
  done
}

# When invoked as a script (not sourced), load state and apply.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=./install-state.sh
  STATE="${STATE:-/root/lib-chroot/install-state.json}"
  _LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
  _INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
  [[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
  # shellcheck disable=SC1090
  source "$_INSTALL_STATE_SH"
  install_state_load "$STATE"
  set -Eeuo pipefail
  _imp_on_err() {
    local rc=$? lineno=$1
    {
      echo "[chroot:impermanence] FAILED"
      echo "  line:    $lineno"
      echo "  command: $BASH_COMMAND"
      echo "  funcs:   ${FUNCNAME[*]:1}"
      echo "  rc:      $rc"
    } >&2
    exit "$rc"
  }
  trap '_imp_on_err $LINENO' ERR
  [[ "${IMP_DEBUG:-0}" == "1" ]] && set -x
  impermanence_apply
fi
