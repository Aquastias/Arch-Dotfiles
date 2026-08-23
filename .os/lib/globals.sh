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
# read through the layout_* accessors at the bottom of this file (ADR 0034).
#
#   LAYOUT_ESP_PARTS[]       ESP partition paths; index 0 = primary (/boot/efi),
#                            length >= 1 after layout_plan().
#   LAYOUT_OS_POOL_NAME      OS pool name (e.g. "rpool").
#   LAYOUT_DATA_POOL_NAMES[] Data pool names to export (Combined + every
#                            Standalone). Empty when none.
# =============================================================================

# shellcheck disable=SC2034  # all vars consumed by other sourced modules

# "single" | "multi" — set by detect_mode() in config.sh
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
LAYOUT_FSTAB_EXTRA=""    # adapter's fstab tail appended by write_fstab
                         # (zfs: auto-mount note; ext4: root + swap lines)
LAYOUT_CRYPTTAB=""       # adapter's /etc/crypttab body (encrypted non-ZFS roots;
                         # empty otherwise) written by write_crypttab

# ─────────────────────────────────────────────────────────────────────────────
# LAYOUT RECORD — read interface (ADR 0043)
# ─────────────────────────────────────────────────────────────────────────────
# The multi-disk adapter resolves a richer model than the LAYOUT_* scalars:
# per-group topology, Standalone Data Pool names/mounts/topologies, folded
# leftover OS disks. Consumers read it ONLY through these accessors, never the
# adapter-private _LAYOUT_IMPL_*. All are safe when the model is absent
# (single-disk / non-ZFS root): they emit nothing / rc 1 rather than aborting an
# undeclared array under `set -u`.

# layout_has_leftover — rc 0 iff an interactively-folded leftover OS-disk pool
# exists. The `declare -p` guard short-circuits before the subscript is touched,
# so a single-mode run (array never declared) does not abort under `set -u`.
layout_has_leftover() {
  declare -p _LAYOUT_IMPL_STORAGE_PARTS &>/dev/null || return 1
  [[ -v _LAYOUT_IMPL_STORAGE_PARTS[_leftover] ]]
}

# layout_leftover_parts — space-separated device list folded into the leftover
# pool ("" when none).
layout_leftover_parts() {
  declare -p _LAYOUT_IMPL_STORAGE_PARTS &>/dev/null || return 0
  printf '%s' "${_LAYOUT_IMPL_STORAGE_PARTS[_leftover]:-}"
}

# layout_os_topology / layout_os_disk — the OS pool's resolved topology and (when
# topology is `none`) the single OS disk.
layout_os_topology() { printf '%s' "${_LAYOUT_IMPL_OS_TOPOLOGY:-}"; }
layout_os_disk()     { printf '%s' "${_LAYOUT_IMPL_OS_DISK:-}"; }

# layout_leftover_disks — OS disks folded into the data pool, one per line
# (nothing when none).
layout_leftover_disks() {
  declare -p _LAYOUT_IMPL_LEFTOVER_DISKS &>/dev/null || return 0
  ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]})) || return 0
  printf '%s\n' "${_LAYOUT_IMPL_LEFTOVER_DISKS[@]}"
}

# layout_group_topology <group> — resolved topology for a Storage Group name (or
# the synthetic `_leftover`); "" when the adapter recorded none.
layout_group_topology() {
  declare -p _LAYOUT_IMPL_TOPOLOGIES &>/dev/null || return 0
  printf '%s' "${_LAYOUT_IMPL_TOPOLOGIES[$1]:-}"
}

# layout_data_pool_names — Standalone Data Pool names, one per line.
layout_data_pool_names() {
  declare -p _LAYOUT_IMPL_DATA_POOL_NAMES &>/dev/null || return 0
  ((${#_LAYOUT_IMPL_DATA_POOL_NAMES[@]})) || return 0
  printf '%s\n' "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"
}

# layout_data_pool_mount <name> / layout_data_pool_topo <name> — a Standalone
# Data Pool's mountpoint and topology.
layout_data_pool_mount() {
  declare -p _LAYOUT_IMPL_DATA_POOL_MOUNT &>/dev/null || return 0
  printf '%s' "${_LAYOUT_IMPL_DATA_POOL_MOUNT[$1]:-}"
}
layout_data_pool_topo() {
  declare -p _LAYOUT_IMPL_DATA_POOL_TOPO &>/dev/null || return 0
  printf '%s' "${_LAYOUT_IMPL_DATA_POOL_TOPO[$1]:-}"
}
