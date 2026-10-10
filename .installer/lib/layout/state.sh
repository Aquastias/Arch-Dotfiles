#!/usr/bin/env bash
# =============================================================================
# lib/layout/state.sh — Layout Record read interface (ADR 0043)
# =============================================================================
# Used by: lib/common.sh (host side), lib/zfs/pool-owners.sh,
# lib/config/lifecycle.sh. Not staged into the chroot (lib/globals.sh is).
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

# layout_data_pool_mount <name> / layout_data_pool_topology <name> — a
# Standalone Data Pool's mountpoint and topology.
layout_data_pool_mount() {
  declare -p _LAYOUT_IMPL_DATA_POOL_MOUNT &>/dev/null || return 0
  printf '%s' "${_LAYOUT_IMPL_DATA_POOL_MOUNT[$1]:-}"
}
layout_data_pool_topology() {
  declare -p _LAYOUT_IMPL_DATA_POOL_TOPO &>/dev/null || return 0
  printf '%s' "${_LAYOUT_IMPL_DATA_POOL_TOPO[$1]:-}"
}
