#!/usr/bin/env bash
# =============================================================================
# lib/globals.sh — Cross-module globals and layout contract
# =============================================================================
# Sourced by common.sh. All variables that cross file boundaries live here so
# their defaults and contracts are visible in one place.
#
# LAYOUT CONTRACT
# ───────────────
# layout_plan() MUST populate the LAYOUT_* variables before returning. Consumers
# (chroot.sh, finalize.sh) read these only, never the layout-private
# _LAYOUT_IMPL_*, so they work in either mode. The richer multi-disk model is
# read through the layout_* accessors in lib/layout/state.sh (ADR 0034).
#
#   LAYOUT_ESP_PARTS[]       ESP partition paths; index 0 = primary (/boot/efi),
#                            length >= 1 after layout_plan().
#   LAYOUT_OS_POOL_NAME      OS pool name (e.g. "rpool").
#   LAYOUT_DATA_POOL_NAMES[] Data pool names to export (Combined + every
#                            Standalone). Empty when none.
# =============================================================================

# shellcheck disable=SC2034  # all vars consumed by other sourced modules

# "single" | "multi" — set by lifecycle_detect_mode() in config/lifecycle.sh
INSTALL_MODE=""
PICK_RESULT=""           # last result from pick_option() in common.sh

# Default disk-encryption passphrase (ADR 0059). Eight chars, NOT five like the
# account default: ZFS keyformat=passphrase rejects shorter at pool creation.
# Runtime default only — never written to Config State, Save, or Export.
# Default-assigned (not readonly) so re-sourcing (guided subprocesses) is
# idempotent.
: "${INSTALL_DEFAULT_ENC_PASSPHRASE:=12345678}"

LAYOUT_ESP_PARTS=()      # populated by layout_plan() — see contract above
LAYOUT_OS_POOL_NAME=""   # populated by layout_plan()
LAYOUT_DATA_POOL_NAMES=() # populated by layout_plan(); data pools to export
# Filesystem-agnostic boot record (ADR 0043): the Root Layout Adapter publishes
# these before install_state_write so the bootloader + initcpio stay FS-blind.
LAYOUT_ROOT_CMDLINE=""   # root= cmdline (zfs: root=ZFS=…; ext4: root=UUID=…)
LAYOUT_HOOKS=""          # mkinitcpio HOOKS list (space-separated hook names)
LAYOUT_FSTAB_EXTRA=""    # adapter's fstab tail appended by chroot_write_fstab
                         # (zfs: auto-mount note; ext4: root + swap lines)
LAYOUT_CRYPTTAB=""       # adapter's /etc/crypttab body (encrypted non-ZFS roots;
                         # empty otherwise) written by chroot_write_crypttab

