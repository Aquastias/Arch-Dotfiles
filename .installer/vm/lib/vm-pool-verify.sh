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
vm_dir_owned_by() {
  local mp="$1" user="$2"
  [[ "$(stat -c '%U' "$mp" 2>/dev/null)" == "$user" ]]
}

# 0 if <user> can write to <mountpoint> (the point of pool ownership — being
# able to save files without sudo). Tested as the user so ACL grants count.
vm_dir_writable_by() {
  local mp="$1" user="$2"
  su - "$user" -c "test -w '$mp'" >/dev/null 2>&1
}

# 0 if <dataset> is currently mounted at <mountpoint>.
vm_dataset_mounted_at() {
  local ds="$1" mp="$2" got_mounted got_mp
  got_mounted="$(zfs get -H -o value mounted "$ds" 2>/dev/null)"
  got_mp="$(zfs get -H -o value mountpoint "$ds" 2>/dev/null)"
  [[ "$got_mounted" == "yes" && "$got_mp" == "$mp" ]]
}

# 0 if something is currently mounted at <mountpoint>. Non-ZFS data groups
# (ADR 0043: ext4/xfs/btrfs disks) have no zpool/dataset to query — their mount
# is confirmed via findmnt.
vm_fs_mounted_at() {
  findmnt -rno TARGET "$1" >/dev/null 2>&1
}

# 0 if every leaf vdev of every pool in VM_VERIFY_POOLS[] resolves via
# /dev/disk/by-id (stable). Flags bare kernel names (/dev/sdX, /dev/nvme…,
# /dev/vd…) — pools recorded that way fail to import after disk-enumeration
# reordering across reboots ("one or more devices is currently unavailable",
# ADR 0028). `zpool status -P` prints the path as recorded in the label/cache.
vm_pool_vdevs_stable() {
  local rc=0 p tok
  for p in "${VM_VERIFY_POOLS[@]}"; do
    for tok in $(zpool status -P "$p" 2>/dev/null); do
      case "$tok" in
      /dev/disk/by-id/*) ;;                       # stable — good
      /dev/sd* | /dev/nvme* | /dev/vd* | /dev/mmcblk* | /dev/hd*)
        echo "UNSTABLE VDEV in $p: $tok" >&2
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
  local rc=0 p entry ds mp
  for p in "${VM_VERIFY_POOLS[@]}"; do
    if ! vm_pool_imported "$p"; then
      echo "MISSING POOL: $p" >&2
      rc=1
    fi
  done
  for entry in "${VM_VERIFY_MOUNTS[@]}"; do
    ds="${entry%%:*}"
    mp="${entry#*:}"
    if ! vm_dataset_mounted_at "$ds" "$mp"; then
      echo "NOT MOUNTED: $ds at $mp" >&2
      rc=1
    fi
  done
  for entry in "${VM_VERIFY_FS_MOUNTS[@]:-}"; do
    [[ -n "$entry" ]] || continue
    if ! vm_fs_mounted_at "$entry"; then
      echo "NOT MOUNTED (fs): $entry" >&2
      rc=1
    fi
  done
  for entry in "${VM_VERIFY_OWNED[@]:-}"; do
    [[ -n "$entry" ]] || continue
    mp="${entry%:*}"
    local user="${entry##*:}"
    if ! vm_dir_owned_by "$mp" "$user"; then
      echo "NOT OWNED: $mp by $user" >&2
      rc=1
    elif ! vm_dir_writable_by "$mp" "$user"; then
      echo "NOT WRITABLE: $mp by $user" >&2
      rc=1
    fi
  done
  if [[ "${VM_VERIFY_BYID:-false}" == "true" ]]; then
    vm_pool_vdevs_stable || rc=1
  fi
  return "$rc"
}
