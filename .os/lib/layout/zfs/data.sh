#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/data.sh — ZFS Data Group Formatter (ADR 0043)
# =============================================================================
# The per-filesystem leaf the layout dispatch (data_formatter_source zfs)
# sources — peer to ext4/xfs/btrfs's data.sh, so create_data_pools formats every
# Standalone Data Pool through the SAME data_group_create seam regardless of the
# root filesystem. Formerly this block lived inline in the ZFS multi Root Adapter
# (zfs/multi.sh), which made the seam asymmetric (one arm = a 1000-line monolith)
# and welded the data-pool feature to a ZFS+multi root.
#
# A ZFS data group is a zpool (not a bare mkfs'd partition): its vdev spec comes
# from the group topology + partitions, and encryption uses the keyfile-on-root
# model — an encrypted DATA pool auto-loads its raw key POST-boot from a keyfile
# on the already-unlocked root, so the operator types one secret per boot, never
# a second prompt. `ashift` is a ZFS-only knob read from the layout record (an
# intra-adapter global set by the ZFS multi Root Adapter's resolve_data_pools).
#
# Disk-touching (data_group_create) is VM-gated, like the non-ZFS core. Requires
# at call time: lib/common.sh (info/section), MOUNT_ROOT, and the layout record
# global _LAYOUT_IMPL_DATA_POOL_ASHIFT.
# =============================================================================

# _zpool_create / build_vdev_spec / ENC_OPTS — the ZFS pool primitives.
[[ "$(type -t _zpool_create)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../../zfs/pools.sh"
# The shared per-group crypto plan emitter (keyfile/mapper/crypttab) — sibling.
[[ "$(type -t data_group_crypto)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../nonzfs/datacrypt.sh"

# Write a Standalone Data Pool's 32-byte raw key to BOTH the install-tree path
# (which persists into the booted system and survives impermanence rollback via
# the curated /etc/cryptsetup-keys.d dir) AND the live path. `zpool create` then
# reads the same key whether it resolves keylocation=file://… against the altroot
# (-R MOUNT_ROOT) or the live filesystem; the live copy is ephemeral tmpfs.
_zfs_gen_data_keyfile() {
  local install_abs="$1" live_abs="$2"
  install -Dm600 /dev/null "$install_abs"
  head -c32 /dev/urandom >"$install_abs"
  install -Dm600 "$install_abs" "$live_abs"
}

# zfs_data_pool_enc_opts <encrypted> <name> — project the ZFS branch of the
# shared per-group crypto plan (nonzfs/datacrypt.sh) into what the pool create
# needs: a `keyfile=<path>` (where the caller must write the raw key) and the
# `opts=<tokens>` (`-O encryption/keyformat/keylocation`) replacing the global
# passphrase-prompt ENC_OPTS for this pool. Plaintext round-trips to empty both.
# Pure: string transforms, no disk access.
zfs_data_pool_enc_opts() {
  local encrypted="$1" name="$2"

  local keyfile="" opts=""
  if [[ "$encrypted" == "true" ]]; then
    # zfs is the data pool's filesystem; the UUID arg is unused on the zfs path.
    local plan
    plan="$(data_group_crypto true zfs "$name" UNUSED)"
    keyfile="$(printf '%s\n' "$plan" | grep -E '^keyfile=' | cut -d= -f2-)"
    opts="$(printf '%s\n' "$plan" | grep -E '^zfs_keyload=' | cut -d= -f2-)"
  fi

  printf 'keyfile=%s\n' "$keyfile"
  printf 'opts=%s\n'    "$opts"
}

# Disk-touching: create one ZFS Standalone Data Pool + its single data dataset.
#   data_group_create <fs> <name> <encrypted> <mount> <topology> <part...>
# The uniform Data Group Formatter seam (peer to the non-ZFS core's signature);
# <fs> is always "zfs" here. `ashift` (ZFS-only) is read from the layout record.
# An encrypted pool writes its keyfile-on-root first, then creates with file://
# key-load opts (never a second prompt); a plaintext pool creates bare.
data_group_create() {
  # arg 1 is the filesystem — always "zfs" for this leaf; consumed by the seam
  # for symmetry with the non-ZFS formatters, unused here.
  local name="$2" encrypted="$3" mount="$4" topology="$5"
  shift 5
  local parts=("$@")
  local ashift="${_LAYOUT_IMPL_DATA_POOL_ASHIFT[$name]:-12}"

  local sel keyfile opts
  sel="$(zfs_data_pool_enc_opts "$encrypted" "$name")"
  keyfile="$(printf '%s\n' "$sel" | grep -E '^keyfile=' | cut -d= -f2-)"
  opts="$(printf '%s\n' "$sel" | grep -E '^opts=' | cut -d= -f2-)"
  # ENC_OPTS is consumed by _zpool_create (the global it word-splits into the
  # zpool create command); read -ra splits the controlled -O token string. It is
  # local so this pool's opts never leak into a later create.
  local ENC_OPTS=()
  # shellcheck disable=SC2034
  read -ra ENC_OPTS <<<"$opts"
  [[ -n "$keyfile" ]] \
    && _zfs_gen_data_keyfile "${MOUNT_ROOT}${keyfile}" "${keyfile}"

  local vdev_spec
  vdev_spec="$(build_vdev_spec "$topology" "${parts[@]}")"
  info "Data pool: ${name}  topology: ${topology}"
  info "vdev: ${vdev_spec}"

  # SC2086 (intentional): vdev_spec must be word-split into multiple args for
  # _zpool_create. Built from controlled inputs in build_vdev_spec.
  # shellcheck disable=SC2086
  _zpool_create "${name}" "${ashift}" $vdev_spec

  # Data lives in one child dataset; the pool root stays unmounted
  # (canmount=off from _zpool_create) — house style (ADR 0027).
  zfs create -o mountpoint="${mount}" "${name}/data"
  info "  ${name}/data → ${mount}"
}
