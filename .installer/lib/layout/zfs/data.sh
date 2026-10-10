#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/data.sh — ZFS Data Group Formatter (ADR 0043)
# =============================================================================
# The per-filesystem leaf the layout dispatch (data_formatter_source zfs)
# sources — peer to ext4/xfs/btrfs's data.sh, so layout_create_data_pools formats every
# Standalone Data Pool through the SAME data_formatter_create_group seam regardless of the
# root filesystem. Formerly this block lived inline in the ZFS multi Root Adapter
# (zfs/multi.sh), which made the seam asymmetric (one arm = a 1000-line monolith)
# and welded the data-pool feature to a ZFS+multi root.
#
# A ZFS data group is a zpool (not a bare mkfs'd partition): its vdev spec comes
# from the group topology + partitions, and encryption uses the keyfile-on-root
# model — an encrypted DATA pool auto-loads its raw key POST-boot from a keyfile
# on the already-unlocked root, so the operator types one secret per boot, never
# a second prompt. `ashift` is a ZFS-only knob read from the layout record (an
# intra-adapter global set by the ZFS multi Root Adapter's layout_resolve_data_pools).
#
# Disk-touching (data_formatter_create_group) is VM-gated, like the non-ZFS core. Requires
# at call time: lib/common.sh (info/section), MOUNT_ROOT, and the layout record
# global _LAYOUT_IMPL_DATA_POOL_ASHIFT.
# =============================================================================

# zfs_create_pool / zfs_vdev_spec / ZFS_ENCRYPTION_OPTIONS — the ZFS pool primitives.
declare -F zfs_create_pool >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../../zfs/pools.sh"
# The shared per-group crypto plan emitter (keyfile/mapper/crypttab) — sibling.
declare -F layout_data_group_crypto >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../nonzfs/datacrypt.sh"
# The shared `key=value` plan-field reader (layout_plan_field) — layout core.
declare -F layout_plan_field >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../core.sh"

# Write a Standalone Data Pool's 32-byte raw key to BOTH the install-tree path
# (which persists into the booted system and survives impermanence rollback via
# the curated /etc/cryptsetup-keys.d dir) AND the live path. `zpool create` then
# reads the same key whether it resolves keylocation=file://… against the altroot
# (-R MOUNT_ROOT) or the live filesystem; the live copy is ephemeral tmpfs.
_zfs_data_generate_keyfile() {
  local install_abs="$1" live_abs="$2"
  install -Dm600 /dev/null "$install_abs"
  dd if=/dev/urandom bs=32 count=1 status=none >"$install_abs"
  install -Dm600 "$install_abs" "$live_abs"
}

# layout_zfs_data_pool_encryption_options <encrypted> <name> — project the ZFS branch of the
# shared per-group crypto plan (nonzfs/datacrypt.sh) into what the pool create
# needs: a `keyfile=<path>` (where the caller must write the raw key) and the
# `opts=<tokens>` (`-O encryption/keyformat/keylocation`) replacing the global
# passphrase-prompt ZFS_ENCRYPTION_OPTIONS for this pool. Plaintext round-trips to empty both.
# Pure: string transforms, no disk access.
layout_zfs_data_pool_encryption_options() {
  local encrypted="$1" name="$2"

  local keyfile="" options=""
  if [[ "$encrypted" == "true" ]]; then
    # zfs is the data pool's filesystem; the UUID arg is unused on the zfs path.
    local plan
    plan="$(layout_data_group_crypto true zfs "$name" UNUSED)"
    keyfile="$(layout_plan_field keyfile <<<"$plan")"
    options="$(layout_plan_field zfs_keyload <<<"$plan")"
  fi

  printf 'keyfile=%s\n' "$keyfile"
  printf 'opts=%s\n'    "$options"
}

# Disk-touching: create one ZFS Standalone Data Pool + its single data dataset.
#   data_formatter_create_group <fs> <name> <encrypted> <mount> <topology> <part...>
# The uniform Data Group Formatter seam (peer to the non-ZFS core's signature);
# <fs> is always "zfs" here. `ashift` (ZFS-only) is read from the layout record.
# An encrypted pool writes its keyfile-on-root first, then creates with file://
# key-load opts (never a second prompt); a plaintext pool creates bare.
data_formatter_create_group() {
  # arg 1 is the filesystem — always "zfs" for this leaf; consumed by the seam
  # for symmetry with the non-ZFS formatters, unused here.
  local name="$2" encrypted="$3" mount="$4" topology="$5"
  shift 5
  local parts=("$@")
  local ashift="${_LAYOUT_IMPL_DATA_POOL_ASHIFT[$name]:-12}"

  local sel keyfile options
  sel="$(layout_zfs_data_pool_encryption_options "$encrypted" "$name")"
  keyfile="$(layout_plan_field keyfile <<<"$sel")"
  options="$(layout_plan_field opts <<<"$sel")"
  # ZFS_ENCRYPTION_OPTIONS is consumed by zfs_create_pool (the global it word-splits into the
  # zpool create command); read -ra splits the controlled -O token string. It is
  # local so this pool's opts never leak into a later create.
  local ZFS_ENCRYPTION_OPTIONS=()
  # shellcheck disable=SC2034
  read -ra ZFS_ENCRYPTION_OPTIONS <<<"$options"
  [[ -n "$keyfile" ]] \
    && _zfs_data_generate_keyfile "${MOUNT_ROOT}${keyfile}" "${keyfile}"

  local vdev_spec
  vdev_spec="$(zfs_vdev_spec "$topology" "${parts[@]}")"
  info "Data pool: ${name}  topology: ${topology}"
  info "vdev: ${vdev_spec}"

  # SC2086 (intentional): vdev_spec must be word-split into multiple args for
  # zfs_create_pool. Built from controlled inputs in zfs_vdev_spec.
  # shellcheck disable=SC2086
  zfs_create_pool "${name}" "${ashift}" $vdev_spec

  # Data lives in one child dataset; the pool root stays unmounted
  # (canmount=off from zfs_create_pool) — house style (ADR 0027).
  zfs create -o mountpoint="${mount}" "${name}/data"
  info "  ${name}/data → ${mount}"
}
