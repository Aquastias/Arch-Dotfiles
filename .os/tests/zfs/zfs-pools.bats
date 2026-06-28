#!/usr/bin/env bats
# Tests for .os/lib/zfs/pools.sh — ZFS pool primitives.
# Covers: build_vdev_spec (pure), build_enc_opts (config-driven), ram_gib.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/zfs/pools.sh
  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  source "$BATS_TEST_DIRNAME/../../lib/zfs/pools.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  printf '%s\n' "$1" > "$CONFIG_FILE"
}

# ── build_vdev_spec ───────────────────────────────────────────────────────────

@test "build_vdev_spec: stripe emits all parts space-separated" {
  run build_vdev_spec stripe /dev/sda1 /dev/sdb1
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda1 /dev/sdb1" ]
}

@test "build_vdev_spec: stripe with single part emits just that part" {
  run build_vdev_spec stripe /dev/nvme0n1p2
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/nvme0n1p2" ]
}

@test "build_vdev_spec: mirror emits mirror prefix + all parts" {
  run build_vdev_spec mirror /dev/sda1 /dev/sdb1
  [ "$status" -eq 0 ]
  [ "$output" = "mirror /dev/sda1 /dev/sdb1" ]
}

@test "build_vdev_spec: none emits only the first part" {
  run build_vdev_spec none /dev/sda1 /dev/sdb1
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda1" ]
}

@test "build_vdev_spec: raidz1 emits raidz1 prefix + all parts" {
  run build_vdev_spec raidz1 /dev/sda1 /dev/sdb1 /dev/sdc1
  [ "$status" -eq 0 ]
  [ "$output" = "raidz1 /dev/sda1 /dev/sdb1 /dev/sdc1" ]
}

@test "build_vdev_spec: raidz2 emits raidz2 prefix + all parts" {
  run build_vdev_spec raidz2 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1
  [ "$status" -eq 0 ]
  [ "$output" = "raidz2 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1" ]
}

@test "build_vdev_spec: independent emits parts space-separated" {
  run build_vdev_spec independent /dev/sda1 /dev/sdb1
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda1 /dev/sdb1" ]
}

@test "build_vdev_spec: unknown topology exits non-zero" {
  run build_vdev_spec bogus /dev/sda1
  [ "$status" -ne 0 ]
}

# ── _zfs_stable_part_path / _zpool_translate_vdev (multi-disk reorder) ───────
# Regression: pools created with bare /dev/sdX record that kernel name in the
# label + zpool.cache. On a multi-disk machine the enumeration order changes
# across reboots, so the cached path points at a different disk → import fails
# ("one or more devices is currently unavailable"). Pools must be created via
# stable /dev/disk/by-id paths instead. ZFS_BYID_DIR overrides the search dir.

# Builds a fake /dev/disk/by-id with id->kernel-node symlinks; isolates the
# by-partuuid tier to an empty dir so the host's real one never leaks in.
# Echoes the by-id dir.
_fake_byid() {
  local dir="$TEST_DIR/by-id"
  mkdir -p "$dir" "$TEST_DIR/dev" "$TEST_DIR/empty"
  ZFS_BYPARTUUID_DIR="$TEST_DIR/empty"
  : > "$TEST_DIR/dev/sdb1"
  : > "$TEST_DIR/dev/sdc1"
  ln -sf "$TEST_DIR/dev/sdb1" "$dir/ata-FAKE_DISK_B-part1"
  ln -sf "$TEST_DIR/dev/sdb1" "$dir/wwn-0xb-part1"
  ln -sf "$TEST_DIR/dev/sdc1" "$dir/ata-FAKE_DISK_C-part1"
  printf '%s' "$dir"
}

@test "_zfs_stable_part_path: maps a kernel part to its by-id symlink" {
  ZFS_BYID_DIR="$(_fake_byid)"
  run _zfs_stable_part_path "$TEST_DIR/dev/sdb1"
  [ "$status" -eq 0 ]
  [ "$output" = "$ZFS_BYID_DIR/ata-FAKE_DISK_B-part1" ]
}

@test "_zfs_stable_part_path: prefers a non-wwn id over wwn" {
  ZFS_BYID_DIR="$(_fake_byid)"
  run _zfs_stable_part_path "$TEST_DIR/dev/sdb1"
  [[ "$output" != *"/wwn-"* ]]
}

@test "_zfs_stable_part_path: unmatched part falls back to input unchanged" {
  ZFS_BYID_DIR="$(_fake_byid)"
  run _zfs_stable_part_path /dev/sdz9
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdz9" ]
}

@test "_zfs_stable_part_path: falls back to by-partuuid when no by-id maps" {
  ZFS_BYID_DIR="$TEST_DIR/by-id"        # exists but has no matching link
  ZFS_BYPARTUUID_DIR="$TEST_DIR/by-partuuid"
  mkdir -p "$ZFS_BYID_DIR" "$ZFS_BYPARTUUID_DIR" "$TEST_DIR/dev"
  : > "$TEST_DIR/dev/sdd1"
  ln -sf "$TEST_DIR/dev/sdd1" "$ZFS_BYPARTUUID_DIR/1234-abcd"
  run _zfs_stable_part_path "$TEST_DIR/dev/sdd1"
  [ "$status" -eq 0 ]
  [ "$output" = "$ZFS_BYPARTUUID_DIR/1234-abcd" ]
}

@test "_zfs_stable_part_path: no stable link anywhere falls back to input" {
  ZFS_BYID_DIR="$TEST_DIR/nope"
  ZFS_BYPARTUUID_DIR="$TEST_DIR/nope2"
  mkdir -p "$TEST_DIR/dev"
  : > "$TEST_DIR/dev/sdb1"
  run _zfs_stable_part_path "$TEST_DIR/dev/sdb1"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/dev/sdb1" ]
}

@test "_zpool_translate_vdev: topology keyword passes through, devs map by-id" {
  ZFS_BYID_DIR="$(_fake_byid)"
  run _zpool_translate_vdev mirror "$TEST_DIR/dev/sdb1" "$TEST_DIR/dev/sdc1"
  [ "$status" -eq 0 ]
  [ "$output" = "mirror $ZFS_BYID_DIR/ata-FAKE_DISK_B-part1 \
$ZFS_BYID_DIR/ata-FAKE_DISK_C-part1" ]
}

# ── _zfs_validate_pool_topology (pure, ADR 0027) ─────────────────────────────

@test "_zfs_validate_pool_topology: stripe with one disk is valid" {
  run _zfs_validate_pool_topology stripe 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_zfs_validate_pool_topology: mirror with two disks is valid" {
  run _zfs_validate_pool_topology mirror 2
  [ "$status" -eq 0 ]
}

@test "_zfs_validate_pool_topology: raidz1 with two disks is valid" {
  run _zfs_validate_pool_topology raidz1 2
  [ "$status" -eq 0 ]
}

@test "_zfs_validate_pool_topology: raidz2 with three disks is valid" {
  run _zfs_validate_pool_topology raidz2 3
  [ "$status" -eq 0 ]
}

@test "_zfs_validate_pool_topology: mirror with one disk gives a reason" {
  run _zfs_validate_pool_topology mirror 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 2"* ]]
}

@test "_zfs_validate_pool_topology: raidz2 with two disks gives a reason" {
  run _zfs_validate_pool_topology raidz2 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 3"* ]]
}

@test "_zfs_validate_pool_topology: none is rejected with guidance" {
  run _zfs_validate_pool_topology none 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"stripe"* ]]
  [[ "$output" == *"data_pools[]"* ]]
}

@test "_zfs_validate_pool_topology: independent is rejected" {
  run _zfs_validate_pool_topology independent 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"independent"* ]]
}

@test "_zfs_validate_pool_topology: unknown topology is rejected" {
  run _zfs_validate_pool_topology raidz3 4
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown topology"* ]]
}

# ── _zfs_valid_pool_name (pure, ADR 0027) ────────────────────────────────────

@test "_zfs_valid_pool_name: reserved word mirror is rejected" {
  run _zfs_valid_pool_name mirror
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserved"* ]]
}

@test "_zfs_valid_pool_name: tank0 is valid" {
  run _zfs_valid_pool_name tank0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_zfs_valid_pool_name: tank-photos is valid" {
  run _zfs_valid_pool_name tank-photos
  [ "$status" -eq 0 ]
}

@test "_zfs_valid_pool_name: leading digit is rejected" {
  run _zfs_valid_pool_name 0tank
  [ "$status" -ne 0 ]
}

@test "_zfs_valid_pool_name: illegal character is rejected" {
  run _zfs_valid_pool_name tank.0
  [ "$status" -ne 0 ]
}

@test "_zfs_valid_pool_name: reserved word raidz1 is rejected" {
  run _zfs_valid_pool_name raidz1
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserved"* ]]
}

@test "_zfs_valid_pool_name: cN prefix is rejected" {
  run _zfs_valid_pool_name c0t0
  [ "$status" -ne 0 ]
  [[ "$output" == *"cN"* ]]
}

# ── _zfs_redundant_size_mismatch (pure, ADR 0027) ────────────────────────────

@test "_zfs_redundant_size_mismatch: mirror over unequal disks warns" {
  run _zfs_redundant_size_mismatch mirror 100 200
  [ "$status" -eq 0 ]
}

@test "_zfs_redundant_size_mismatch: mirror over equal disks does not warn" {
  run _zfs_redundant_size_mismatch mirror 100 100
  [ "$status" -ne 0 ]
}

@test "_zfs_redundant_size_mismatch: stripe over unequal disks does not warn" {
  run _zfs_redundant_size_mismatch stripe 100 200
  [ "$status" -ne 0 ]
}

@test "_zfs_redundant_size_mismatch: single disk does not warn" {
  run _zfs_redundant_size_mismatch mirror 100
  [ "$status" -ne 0 ]
}

@test "_zfs_redundant_size_mismatch: raidz1 unequal warns" {
  run _zfs_redundant_size_mismatch raidz1 100 200 100
  [ "$status" -eq 0 ]
}

@test "_zfs_redundant_size_mismatch: raidz2 equal does not warn" {
  run _zfs_redundant_size_mismatch raidz2 50 50 50
  [ "$status" -ne 0 ]
}

# ── build_enc_opts ────────────────────────────────────────────────────────────

@test "build_enc_opts: encryption false → ENC_OPTS is empty" {
  write_config '{"options": {"encryption": "false"}}'
  build_enc_opts
  [ "${#ENC_OPTS[@]}" -eq 0 ]
}

@test "build_enc_opts: encryption true → ENC_OPTS includes aes-256-gcm" {
  write_config '{"options": {"encryption": "true"}}'
  build_enc_opts
  [ "${#ENC_OPTS[@]}" -gt 0 ]
  [[ "${ENC_OPTS[*]}" == *"aes-256-gcm"* ]]
}

@test "build_enc_opts: encryption=true → ENC_OPTS has keyformat=passphrase" {
  write_config '{"options": {"encryption": "true"}}'
  build_enc_opts
  [[ "${ENC_OPTS[*]}" == *"keyformat=passphrase"* ]]
}

@test "build_enc_opts: missing encryption defaults false → ENC_OPTS empty" {
  write_config '{}'
  build_enc_opts
  [ "${#ENC_OPTS[@]}" -eq 0 ]
}

# ── _enc_opts_prompt ──────────────────────────────────────────────────────────
# The predicate _zpool_create keys its stdin-passphrase pipe on: it pipes the
# boot passphrase ONLY when the active opts ask for it (keylocation=prompt). The
# root pool (prompt) still gets the passphrase; a keyfile-on-root data pool
# (keylocation=file://…) does not, so there is no second prompt.

@test "_enc_opts_prompt: prompt opts → true (passphrase piped)" {
  run _enc_opts_prompt -O encryption=aes-256-gcm -O keyformat=passphrase \
    -O keylocation=prompt
  [ "$status" -eq 0 ]
}

@test "_enc_opts_prompt: keyfile file:// opts → false (no passphrase)" {
  run _enc_opts_prompt -O encryption=aes-256-gcm -O keyformat=raw \
    -O keylocation=file:///etc/cryptsetup-keys.d/tank0.key
  [ "$status" -ne 0 ]
}

@test "_enc_opts_prompt: empty opts (plaintext pool) → false" {
  run _enc_opts_prompt
  [ "$status" -ne 0 ]
}

# ── ram_gib ───────────────────────────────────────────────────────────────────

@test "ram_gib: returns a positive integer" {
  run ram_gib
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}
