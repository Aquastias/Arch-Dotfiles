#!/usr/bin/env bash
# =============================================================================
# lib/zfs/vdev-spec.sh — topology + partitions → zpool vdev tokens (pure)
# =============================================================================
# Used by: lib/zfs/pools.sh (sources it), lib/layout/zfs/*.sh via pools.sh.
# =============================================================================

[[ -n "${_ZFS_VDEV_SPEC_SH_SOURCED:-}" ]] && return 0
_ZFS_VDEV_SPEC_SH_SOURCED=1

zfs_vdev_spec() {
  # Converts a topology name and a list of partition paths into a zpool
  # vdev specification string suitable for passing to zpool create.
  #
  # Usage: zfs_vdev_spec <topology> <part1> [part2] ...
  # Outputs: the vdev spec string (echoed to stdout)
  #
  # Topologies:
  #   mirror      — "mirror part1 part2 ..."  (one N-way mirror: 2 disks or
  #                                             an odd count); an even count
  #                                             of 4+ pairs into striped 2-way
  #                                             mirrors (RAID-10, the menu's
  #                                             "2 × 2-disk mirrors")
  #   stripe      — "part1 part2 ..."          (striped, no redundancy)
  #   none        — "part1"                    (single disk, first only)
  #   raidz1      — "raidz1 part1 part2 ..."  (1 parity disk; `raidz` alias)
  #   raidz2      — "raidz2 part1 part2 ..."  (2 parity disks)
  #   independent — "part1 part2 ..."          (each disk its own vdev;
  #                                             same as stripe at pool level
  #                                             but datasets are per-disk)

  local topology="$1"
  shift
  local parts=("$@")
  case "$topology" in
  mirror)      _vdev_spec_mirror "${parts[@]}" ;;
  stripe)      echo "${parts[*]}" ;;
  none)        echo "${parts[0]}" ;;
  raidz | raidz1) echo "raidz1 ${parts[*]}" ;;
  raidz2)      echo "raidz2 ${parts[*]}" ;;
  independent) echo "${parts[*]}" ;;
  *)           error "Unknown topology: '$topology'" ;;
  esac
}

# _vdev_spec_mirror <part>... — the mirror vdevs for zfs_vdev_spec.
_vdev_spec_mirror() {
  local -a parts=("$@")
  if ((${#parts[@]} < 4 || ${#parts[@]} % 2)); then
    echo "mirror ${parts[*]}"
    return 0
  fi
  local spec="" index
  for ((index = 0; index < ${#parts[@]}; index += 2)); do
    spec+="${spec:+ }mirror ${parts[index]} ${parts[index + 1]}"
  done
  echo "$spec"
}
