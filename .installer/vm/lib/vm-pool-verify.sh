#!/usr/bin/env bash
# =============================================================================
# lib/vm-pool-verify.sh — booted-system ZFS pool/mount verifier (test-only)
# =============================================================================
# Runs on a freshly-installed test VM at first boot to confirm the install
# brought every expected pool up and mounted its data dataset. Used by the
# multi-data-pools VM smoke test (issue 06 / ADR 0027); never part of a
# production install.
#
# Behaviour is driven by arrays the caller sets before invoking vm_pool_verify:
#   VM_VERIFY_POOLS[]   — pool names that must be imported (e.g. rpool tank0)
#   VM_VERIFY_MOUNTS[]  — "<dataset>:<mountpoint>" pairs that must be mounted
#                         there (e.g. tank0/data:/data/tank0)
#   VM_VERIFY_OWNED[]   — "<mountpoint>:<user>" pairs that must be owned by, and
#                         writable by, <user> (pool-owners, ADR 0031)
#
# The system is queried through `zpool` / `zfs` so unit tests can stub them.
# Returns 0 only when every check passes; prints each failure to stderr.
# =============================================================================

# 0 if the pool is imported (visible to `zpool list`).
vm_pool_imported() {
  zpool list -H -o name "$1" >/dev/null 2>&1
}

# 0 if the directory at <mountpoint> is owned by <user>.
vm_directory_owned_by() {
  local mountpoint="$1" user="$2"
  [[ "$(stat -c '%U' "$mountpoint" 2>/dev/null)" == "$user" ]]
}

# 0 if <user> can write to <mountpoint> (the point of pool ownership — being
# able to save files without sudo). Tested as the user so ACL grants count.
vm_directory_writable_by() {
  local mountpoint="$1" user="$2"
  su - "$user" -c "test -w '$mountpoint'" >/dev/null 2>&1
}

# 0 if <dataset> is currently mounted at <mountpoint>.
vm_dataset_mounted_at() {
  local dataset="$1" mountpoint="$2" got_mounted got_mountpoint
  got_mounted="$(zfs get -H -o value mounted "$dataset" 2>/dev/null)"
  got_mountpoint="$(zfs get -H -o value mountpoint "$dataset" 2>/dev/null)"
  [[ "$got_mounted" == "yes" && "$got_mountpoint" == "$mountpoint" ]]
}

# 0 if something is currently mounted at <mountpoint>. Non-ZFS data groups
# (ADR 0043: ext4/xfs/btrfs disks) have no zpool/dataset to query — their mount
# is confirmed via findmnt.
vm_filesystem_mounted_at() {
  findmnt -rno TARGET "$1" >/dev/null 2>&1
}

# 0 if every leaf vdev of every pool in VM_VERIFY_POOLS[] resolves via
# /dev/disk/by-id (stable). Flags bare kernel names (/dev/sdX, /dev/nvme…,
# /dev/vd…) — pools recorded that way fail to import after disk-enumeration
# reordering across reboots ("one or more devices is currently unavailable",
# ADR 0028). `zpool status -P` prints the path as recorded in the label/cache.
vm_pool_vdevs_stable() {
  local rc=0 pool token
  for pool in "${VM_VERIFY_POOLS[@]}"; do
    for token in $(zpool status -P "$pool" 2>/dev/null); do
      case "$token" in
      /dev/disk/by-id/*) ;;                       # stable — good
      /dev/sd* | /dev/nvme* | /dev/vd* | /dev/mmcblk* | /dev/hd*)
        echo "UNSTABLE VDEV in $pool: $token" >&2
        rc=1 ;;
      esac
    done
  done
  return "$rc"
}

# Verifies every pool in VM_VERIFY_POOLS[] is imported and every
# "<dataset>:<mountpoint>" in VM_VERIFY_MOUNTS[] is mounted there. When
# VM_VERIFY_BYID=true it also asserts every leaf vdev is a stable by-id path.
# Prints each failure; returns non-zero if any check fails.
vm_pool_verify() {
  local rc=0 pool entry dataset mountpoint
  for pool in "${VM_VERIFY_POOLS[@]}"; do
    if ! vm_pool_imported "$pool"; then
      echo "MISSING POOL: $pool" >&2
      rc=1
    fi
  done
  for entry in "${VM_VERIFY_MOUNTS[@]}"; do
    dataset="${entry%%:*}"
    mountpoint="${entry#*:}"
    if ! vm_dataset_mounted_at "$dataset" "$mountpoint"; then
      echo "NOT MOUNTED: $dataset at $mountpoint" >&2
      rc=1
    fi
  done
  for entry in "${VM_VERIFY_FS_MOUNTS[@]:-}"; do
    [[ -n "$entry" ]] || continue
    if ! vm_filesystem_mounted_at "$entry"; then
      echo "NOT MOUNTED (fs): $entry" >&2
      rc=1
    fi
  done
  for entry in "${VM_VERIFY_OWNED[@]:-}"; do
    [[ -n "$entry" ]] || continue
    mountpoint="${entry%:*}"
    local user="${entry##*:}"
    if ! vm_directory_owned_by "$mountpoint" "$user"; then
      echo "NOT OWNED: $mountpoint by $user" >&2
      rc=1
    elif ! vm_directory_writable_by "$mountpoint" "$user"; then
      echo "NOT WRITABLE: $mountpoint by $user" >&2
      rc=1
    fi
  done
  if [[ "${VM_VERIFY_BYID:-false}" == "true" ]]; then
    vm_pool_vdevs_stable || rc=1
  fi
  return "$rc"
}
