#!/usr/bin/env bash
# =============================================================================
# lib/globals.sh — Cross-module globals and layout contract
# =============================================================================
# Sourced by common.sh. All variables that cross file boundaries live here so
# their defaults and contracts are visible in one place.
#
# LAYOUT CONTRACT
# ───────────────
# layout_plan() (unified in lib/layout/zfs/plan.sh, dispatching to the active mode
# adapter) MUST populate the three LAYOUT_* variables before returning.
# Consumers (chroot.sh, finalize.sh) read these and never reference
# layout-private variables (_LAYOUT_IMPL_*), so they work with either mode
# without changes.
#
#   LAYOUT_ESP_PARTS[]     Resolved ESP partition device paths.
#                          Index 0 = primary (/boot/efi).
#                          Length ≥ 1 after layout_plan() returns — ESP paths
#                          are decided at plan time via part_name (ADR 0034).
#   LAYOUT_OS_POOL_NAME    Resolved OS pool name (e.g. "rpool").
#                          Safe to read after layout_plan() returns.
#   LAYOUT_DATA_POOL_NAMES[] Resolved data pool names to export — the
#                          Combined Data Pool (when present) plus every
#                          Standalone Data Pool. Empty when no data pools.
# =============================================================================

# shellcheck disable=SC2034  # all vars consumed by other sourced modules

# "single" | "multi" — set by detect_mode() in config.sh
INSTALL_MODE=""
PICK_RESULT=""           # last result from pick_option() in common.sh

LAYOUT_ESP_PARTS=()      # populated by layout_plan() — see contract above
LAYOUT_OS_POOL_NAME=""   # populated by layout_plan()
LAYOUT_DATA_POOL_NAMES=() # populated by layout_plan(); data pools to export
# Filesystem-agnostic boot record (ADR 0043): the Root Layout Adapter publishes
# these before install_state_write so the bootloader + initcpio stay FS-blind.
LAYOUT_ROOT_CMDLINE=""   # root= cmdline (zfs: root=ZFS=…; ext4: root=UUID=…)
LAYOUT_HOOKS=""          # mkinitcpio HOOKS list (space-separated hook names)
