#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/plan.sh — ZFS planner specifics (pure: no destructive ops)
# =============================================================================
# The filesystem-agnostic `layout_plan` verb, seam-hook defaults and ESP
# resolution were extracted to lib/layout/core.sh (ADR 0043). This file keeps
# the ZFS-specific pieces the planner needs: the interactive Leftover-Disk
# Adapter and the ZFS boot-record publisher (the _layout_publish_boot override).
#
# Sourced by lib/layout/zfs/common.sh (after core.sh). Requires: lib/common.sh
# (part_name) + the phase/contract helpers in core.sh, available at call time.
# =============================================================================

# ── Leftover-Disk Adapter (interactive by default; substitutable in tests) ───
# A leftover OS disk (topology=none with 2+ OS disks) is either folded into the
# Combined Data Pool or given its own Standalone Data Pool. The planner asks the
# adapter rather than prompting directly, so it stays pure.
#
#   layout_leftover_choice DISK SIZE     → sets LAYOUT_LEFTOVER_CHOICE=fold|own
#   layout_leftover_pool_name DEF TAKEN… → sets LAYOUT_LEFTOVER_POOL_NAME
#
# Out-params mirror the house PICK_RESULT / POOL_NAME_RESULT style. The default
# adapter wraps the existing pick_option / _prompt_pool_name seams.
# Read by the multi adapter's resolve_leftover_disks (hence SC2034).
# shellcheck disable=SC2034
LAYOUT_LEFTOVER_CHOICE=""
# shellcheck disable=SC2034
LAYOUT_LEFTOVER_POOL_NAME=""

layout_leftover_choice() {
  local disk="$1" size="$2"
  pick_option "Leftover disk ${disk} (${size}):" \
    "fold  (into the Combined Data Pool 'dpool')" \
    "own   (its own Standalone Data Pool, single-disk stripe)"
  # pick_option yields the chosen line's first word (fold|own).
  # shellcheck disable=SC2034
  LAYOUT_LEFTOVER_CHOICE="$(printf '%s' "$PICK_RESULT" | awk '{print $1}')"
}

layout_leftover_pool_name() {
  local def="$1"; shift
  _prompt_pool_name "$def" "$@"
  # shellcheck disable=SC2034
  LAYOUT_LEFTOVER_POOL_NAME="$POOL_NAME_RESULT"
}

# ── ZFS boot-record publisher (overrides core's default) ─────────────────────

# Publishes the filesystem-agnostic boot record (ADR 0043) for a ZFS root: the
# `root=ZFS=…` cmdline + the zfs initramfs HOOKS, so the bootloader and initcpio
# read these from install-state instead of hardcoding ZFS. `modconf` is a
# placeholder token — initcpio.sh swaps it for `kmod` at chroot time when the
# newer hook name is present. `zfs-rollback` is inserted before `filesystems`
# under impermanence (rollback after pool import, before any dataset mounts).
# Both fields are knowable at plan time (the pool name is resolved by then).
_layout_publish_boot() {
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_ROOT_CMDLINE="root=ZFS=${LAYOUT_OS_POOL_NAME}/ROOT/arch"
  LAYOUT_ROOT_CMDLINE+=" zfs_import_dir=/dev/disk/by-id"
  local tail="zfs filesystems"
  [[ "$(install_config_impermanence_enabled)" == "true" ]] &&
    tail="zfs zfs-rollback filesystems"
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_HOOKS="base udev autodetect modconf block keyboard ${tail}"
  # ZFS datasets mount via zfs-mount-generator, not fstab; just a note.
  # shellcheck disable=SC2034 # consumed by write_fstab
  LAYOUT_FSTAB_EXTRA="# ZFS datasets are auto-mounted by zfs-mount-generator"
}
