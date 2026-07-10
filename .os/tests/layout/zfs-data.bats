#!/usr/bin/env bats
# Tests for the ZFS Data Group Formatter leaf (lib/layout/zfs/data.sh, ADR 0043)
# — the peer to ext4/xfs/btrfs's data.sh that create_data_pools dispatches to via
# the uniform data_group_create seam. Two surfaces:
#   1. zfs_data_pool_enc_opts — the pure key-load selector (an encrypted DATA
#      pool auto-loads its raw key POST-boot from a keyfile on the already-
#      unlocked root — never re-prompting for the boot passphrase; plaintext
#      round-trips to empty). Formerly the standalone datakey.sh module.
#   2. data_group_create — the disk-touching zpool create (VM-gated in reality),
#      exercised here against mocked pool primitives to pin the flow: keyfile-on-
#      root only when encrypted, ashift from the record, dataset at the mount.

setup() {
  # shellcheck source=../../lib/layout/zfs/data.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/zfs/data.sh"
}

dk_field() { grep -E "^$1=" | cut -d= -f2-; }

# ── zfs_data_pool_enc_opts (pure) ────────────────────────────────────────────

@test "enc-opts: plaintext selects empty keyfile + empty opts" {
  run zfs_data_pool_enc_opts false tank0
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dk_field keyfile)" = "" ]
  [ "$(printf '%s\n' "$output" | dk_field opts)"    = "" ]
}

@test "enc-opts: encrypted selects keyfile-on-root + file:// opts" {
  run zfs_data_pool_enc_opts true tank0
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dk_field keyfile)" \
      = "/etc/cryptsetup-keys.d/tank0.key" ]
  [ "$(printf '%s\n' "$output" | dk_field opts)" \
      = "-O encryption=aes-256-gcm -O keyformat=raw -O keylocation=file:///etc/cryptsetup-keys.d/tank0.key" ]
}

@test "enc-opts: encrypted opts never use keylocation=prompt" {
  run zfs_data_pool_enc_opts true vault
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | dk_field opts)" != *"keylocation=prompt"* ]]
}

# ── data_group_create (disk-touching; primitives mocked) ─────────────────────

# Stub the pool primitives + record the ashift/vdev/dataset a create would run.
mock_create_env() {
  _TRACE="$BATS_TEST_TMPDIR/trace"; : >"$_TRACE"
  MOUNT_ROOT="$BATS_TEST_TMPDIR/root"; mkdir -p "$MOUNT_ROOT"
  info() { :; }
  section() { :; }
  build_vdev_spec() { shift; printf 'VDEV[%s]' "$*"; }
  _zpool_create() { echo "zpool_create name=$1 ashift=$2 vdev=$3" >>"$_TRACE"; }
  _zfs_gen_data_keyfile() { echo "keyfile install=$1 live=$2" >>"$_TRACE"; }
  zfs() { echo "zfs $*" >>"$_TRACE"; }
}

@test "data_group_create: plaintext pool creates zpool + dataset, no keyfile" {
  mock_create_env
  declare -gA _LAYOUT_IMPL_DATA_POOL_ASHIFT=([tank0]=12)
  data_group_create zfs tank0 false /mnt/tank0 stripe /dev/sda1
  grep -q "zpool_create name=tank0 ashift=12" "$_TRACE"
  grep -q "zfs create -o mountpoint=/mnt/tank0 tank0/data" "$_TRACE"
  ! grep -q "keyfile install=" "$_TRACE"
}

@test "data_group_create: encrypted pool writes the keyfile-on-root first" {
  mock_create_env
  declare -gA _LAYOUT_IMPL_DATA_POOL_ASHIFT=([vault]=12)
  data_group_create zfs vault true /mnt/vault mirror /dev/sda1 /dev/sdb1
  grep -q "keyfile install=${MOUNT_ROOT}/etc/cryptsetup-keys.d/vault.key" "$_TRACE"
  grep -q "zpool_create name=vault" "$_TRACE"
}

@test "data_group_create: ashift comes from the layout record (default 12)" {
  mock_create_env
  declare -gA _LAYOUT_IMPL_DATA_POOL_ASHIFT=([tank0]=13)
  data_group_create zfs tank0 false /mnt/tank0 stripe /dev/sda1
  grep -q "zpool_create name=tank0 ashift=13" "$_TRACE"
}
