#!/usr/bin/env bats
# Tests for .installer/lib/zfs/pools.sh — ZFS pool primitives.
# Covers: zfs_vdev_spec (pure), zfs_encryption_options (config-driven), zfs_ram_gib.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/zfs/pools.sh
  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
  source "$BATS_TEST_DIRNAME/../../lib/zfs/pools.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  printf '%s\n' "$1" > "$CONFIG_FILE"
}

# ── zfs_vdev_spec ───────────────────────────────────────────────────────────

@test "zfs_vdev_spec: stripe emits all parts space-separated" {
  run zfs_vdev_spec stripe /dev/sda1 /dev/sdb1
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda1 /dev/sdb1" ]
}

@test "zfs_vdev_spec: stripe with single part emits just that part" {
  run zfs_vdev_spec stripe /dev/nvme0n1p2
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/nvme0n1p2" ]
}

@test "zfs_vdev_spec: mirror emits mirror prefix + all parts" {
  run zfs_vdev_spec mirror /dev/sda1 /dev/sdb1
  [ "$status" -eq 0 ]
  [ "$output" = "mirror /dev/sda1 /dev/sdb1" ]
}

@test "zfs_vdev_spec: none emits only the first part" {
  run zfs_vdev_spec none /dev/sda1 /dev/sdb1
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda1" ]
}

@test "zfs_vdev_spec: raidz1 emits raidz1 prefix + all parts" {
  run zfs_vdev_spec raidz1 /dev/sda1 /dev/sdb1 /dev/sdc1
  [ "$status" -eq 0 ]
  [ "$output" = "raidz1 /dev/sda1 /dev/sdb1 /dev/sdc1" ]
}

@test "zfs_vdev_spec: raidz2 emits raidz2 prefix + all parts" {
  run zfs_vdev_spec raidz2 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1
  [ "$status" -eq 0 ]
  [ "$output" = "raidz2 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1" ]
}

@test "zfs_vdev_spec: independent emits parts space-separated" {
  run zfs_vdev_spec independent /dev/sda1 /dev/sdb1
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda1 /dev/sdb1" ]
}

@test "zfs_vdev_spec: unknown topology exits non-zero" {
  run zfs_vdev_spec bogus /dev/sda1
  [ "$status" -ne 0 ]
}

# ── _pools_stable_partition_path / _pools_translate_vdev (multi-disk reorder) ───────
# Regression: pools created with bare /dev/sdX record that kernel name in the
# label + zpool.cache. On a multi-disk machine the enumeration order changes
# across reboots, so the cached path points at a different disk → import fails
# ("one or more devices is currently unavailable"). Pools must be created via
# stable /dev/disk/by-id paths instead. ZFS_BYID_DIR overrides the search dir.

# Builds a fake /dev/disk/by-id with id->kernel-node symlinks; isolates the
# by-partuuid tier to an empty dir so the host's real one never leaks in.
# Echoes the by-id dir.
_fake_byid() {
  local by_id_directory="$TEST_DIR/by-id"
  mkdir -p "$by_id_directory" "$TEST_DIR/dev" "$TEST_DIR/empty"
  ZFS_BYPARTUUID_DIR="$TEST_DIR/empty"
  : > "$TEST_DIR/dev/sdb1"
  : > "$TEST_DIR/dev/sdc1"
  ln -sf "$TEST_DIR/dev/sdb1" "$by_id_directory/ata-FAKE_DISK_B-part1"
  ln -sf "$TEST_DIR/dev/sdb1" "$by_id_directory/wwn-0xb-part1"
  ln -sf "$TEST_DIR/dev/sdc1" "$by_id_directory/ata-FAKE_DISK_C-part1"
  printf '%s' "$by_id_directory"
}

@test "_pools_stable_partition_path: maps a kernel part to its by-id symlink" {
  ZFS_BYID_DIR="$(_fake_byid)"
  run _pools_stable_partition_path "$TEST_DIR/dev/sdb1"
  [ "$status" -eq 0 ]
  [ "$output" = "$ZFS_BYID_DIR/ata-FAKE_DISK_B-part1" ]
}

@test "_pools_stable_partition_path: prefers a non-wwn id over wwn" {
  ZFS_BYID_DIR="$(_fake_byid)"
  run _pools_stable_partition_path "$TEST_DIR/dev/sdb1"
  [[ "$output" != *"/wwn-"* ]]
}

@test "_pools_stable_partition_path: unmatched part falls back to input unchanged" {
  ZFS_BYID_DIR="$(_fake_byid)"
  run _pools_stable_partition_path /dev/sdz9
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdz9" ]
}

@test "_pools_stable_partition_path: falls back to by-partuuid when no by-id maps" {
  ZFS_BYID_DIR="$TEST_DIR/by-id"        # exists but has no matching link
  ZFS_BYPARTUUID_DIR="$TEST_DIR/by-partuuid"
  mkdir -p "$ZFS_BYID_DIR" "$ZFS_BYPARTUUID_DIR" "$TEST_DIR/dev"
  : > "$TEST_DIR/dev/sdd1"
  ln -sf "$TEST_DIR/dev/sdd1" "$ZFS_BYPARTUUID_DIR/1234-abcd"
  run _pools_stable_partition_path "$TEST_DIR/dev/sdd1"
  [ "$status" -eq 0 ]
  [ "$output" = "$ZFS_BYPARTUUID_DIR/1234-abcd" ]
}

@test "_pools_stable_partition_path: no stable link anywhere falls back to input" {
  ZFS_BYID_DIR="$TEST_DIR/nope"
  ZFS_BYPARTUUID_DIR="$TEST_DIR/nope2"
  mkdir -p "$TEST_DIR/dev"
  : > "$TEST_DIR/dev/sdb1"
  run _pools_stable_partition_path "$TEST_DIR/dev/sdb1"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/dev/sdb1" ]
}

@test "_pools_translate_vdev: topology keyword passes through, devs map by-id" {
  ZFS_BYID_DIR="$(_fake_byid)"
  run _pools_translate_vdev mirror "$TEST_DIR/dev/sdb1" "$TEST_DIR/dev/sdc1"
  [ "$status" -eq 0 ]
  [ "$output" = "mirror $ZFS_BYID_DIR/ata-FAKE_DISK_B-part1 \
$ZFS_BYID_DIR/ata-FAKE_DISK_C-part1" ]
}

# ── _pools_validate_topology (pure, ADR 0027) ─────────────────────────────

@test "_pools_validate_topology: stripe with one disk is valid" {
  run _pools_validate_topology stripe 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_pools_validate_topology: mirror with two disks is valid" {
  run _pools_validate_topology mirror 2
  [ "$status" -eq 0 ]
}

@test "_pools_validate_topology: raidz1 with two disks is valid" {
  run _pools_validate_topology raidz1 2
  [ "$status" -eq 0 ]
}

@test "_pools_validate_topology: raidz2 with three disks is valid" {
  run _pools_validate_topology raidz2 3
  [ "$status" -eq 0 ]
}

@test "_pools_validate_topology: mirror with one disk gives a reason" {
  run _pools_validate_topology mirror 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 2"* ]]
}

@test "_pools_validate_topology: raidz2 with two disks gives a reason" {
  run _pools_validate_topology raidz2 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 3"* ]]
}

@test "_pools_validate_topology: none is rejected with guidance" {
  run _pools_validate_topology none 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"stripe"* ]]
  [[ "$output" == *"data_pools[]"* ]]
}

@test "_pools_validate_topology: independent is rejected" {
  run _pools_validate_topology independent 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"independent"* ]]
}

@test "_pools_validate_topology: unknown topology is rejected" {
  run _pools_validate_topology raidz3 4
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown topology"* ]]
}

# ── zfs_data_pool_topology_ok (filesystem-aware dispatch, ADR 0043) ──────────────
# Per-pool topology validation that dispatches on the data pool's filesystem: a
# zfs pool runs the native vdev validator; a non-zfs pool (btrfs/ext4/xfs) had
# its topology validity already gated by validation.sh, so it passes here — the
# zfs validator must NOT reject a btrfs profile like raid1 as "unknown topology".

@test "zfs_data_pool_topology_ok: btrfs raid1 passes (not a zfs unknown topology)" {
  run zfs_data_pool_topology_ok btrfs raid1 2
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "zfs_data_pool_topology_ok: zfs mirror with one disk still aborts" {
  run zfs_data_pool_topology_ok zfs mirror 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 2"* ]]
}

@test "zfs_data_pool_topology_ok: zfs unknown topology still rejected" {
  run zfs_data_pool_topology_ok zfs raidz3 4
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown topology"* ]]
}

# ── zfs_valid_pool_name (pure, ADR 0027) ────────────────────────────────────

@test "zfs_valid_pool_name: reserved word mirror is rejected" {
  run zfs_valid_pool_name mirror
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserved"* ]]
}

@test "zfs_valid_pool_name: tank0 is valid" {
  run zfs_valid_pool_name tank0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "zfs_valid_pool_name: tank-photos is valid" {
  run zfs_valid_pool_name tank-photos
  [ "$status" -eq 0 ]
}

@test "zfs_valid_pool_name: leading digit is rejected" {
  run zfs_valid_pool_name 0tank
  [ "$status" -ne 0 ]
}

@test "zfs_valid_pool_name: illegal character is rejected" {
  run zfs_valid_pool_name tank.0
  [ "$status" -ne 0 ]
}

@test "zfs_valid_pool_name: reserved word raidz1 is rejected" {
  run zfs_valid_pool_name raidz1
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserved"* ]]
}

@test "zfs_valid_pool_name: cN prefix is rejected" {
  run zfs_valid_pool_name c0t0
  [ "$status" -ne 0 ]
  [[ "$output" == *"cN"* ]]
}

# ── zfs_redundant_size_mismatch (pure, ADR 0027) ────────────────────────────

@test "zfs_redundant_size_mismatch: mirror over unequal disks warns" {
  run zfs_redundant_size_mismatch mirror 100 200
  [ "$status" -eq 0 ]
}

@test "zfs_redundant_size_mismatch: mirror over equal disks does not warn" {
  run zfs_redundant_size_mismatch mirror 100 100
  [ "$status" -ne 0 ]
}

@test "zfs_redundant_size_mismatch: stripe over unequal disks does not warn" {
  run zfs_redundant_size_mismatch stripe 100 200
  [ "$status" -ne 0 ]
}

@test "zfs_redundant_size_mismatch: single disk does not warn" {
  run zfs_redundant_size_mismatch mirror 100
  [ "$status" -ne 0 ]
}

@test "zfs_redundant_size_mismatch: raidz1 unequal warns" {
  run zfs_redundant_size_mismatch raidz1 100 200 100
  [ "$status" -eq 0 ]
}

@test "zfs_redundant_size_mismatch: raidz2 equal does not warn" {
  run zfs_redundant_size_mismatch raidz2 50 50 50
  [ "$status" -ne 0 ]
}

# ── zfs_encryption_options ────────────────────────────────────────────────────────────

@test "zfs_encryption_options: encryption false → ZFS_ENCRYPTION_OPTIONS is empty" {
  write_config '{"options": {"encryption": "false"}}'
  zfs_encryption_options
  [ "${#ZFS_ENCRYPTION_OPTIONS[@]}" -eq 0 ]
}

@test "zfs_encryption_options: encryption true → ZFS_ENCRYPTION_OPTIONS includes aes-256-gcm" {
  write_config '{"options": {"encryption": "true"}}'
  zfs_encryption_options
  [ "${#ZFS_ENCRYPTION_OPTIONS[@]}" -gt 0 ]
  [[ "${ZFS_ENCRYPTION_OPTIONS[*]}" == *"aes-256-gcm"* ]]
}

@test "zfs_encryption_options: encryption=true → ZFS_ENCRYPTION_OPTIONS has keyformat=passphrase" {
  write_config '{"options": {"encryption": "true"}}'
  zfs_encryption_options
  [[ "${ZFS_ENCRYPTION_OPTIONS[*]}" == *"keyformat=passphrase"* ]]
}

@test "zfs_encryption_options: missing encryption defaults false → ZFS_ENCRYPTION_OPTIONS empty" {
  write_config '{}'
  zfs_encryption_options
  [ "${#ZFS_ENCRYPTION_OPTIONS[@]}" -eq 0 ]
}

# ── _pools_prompt_encryption_options ──────────────────────────────────────────────────────────
# The predicate zfs_create_pool keys its stdin-passphrase pipe on: it pipes the
# boot passphrase ONLY when the active opts ask for it (keylocation=prompt). The
# root pool (prompt) still gets the passphrase; a keyfile-on-root data pool
# (keylocation=file://…) does not, so there is no second prompt.

@test "_pools_prompt_encryption_options: prompt opts → true (passphrase piped)" {
  run _pools_prompt_encryption_options -O encryption=aes-256-gcm -O keyformat=passphrase \
    -O keylocation=prompt
  [ "$status" -eq 0 ]
}

@test "_pools_prompt_encryption_options: keyfile file:// opts → false (no passphrase)" {
  run _pools_prompt_encryption_options -O encryption=aes-256-gcm -O keyformat=raw \
    -O keylocation=file:///etc/cryptsetup-keys.d/tank0.key
  [ "$status" -ne 0 ]
}

@test "_pools_prompt_encryption_options: empty opts (plaintext pool) → false" {
  run _pools_prompt_encryption_options
  [ "$status" -ne 0 ]
}

# ── zfs_collect_encryption_passphrase precedence (ADR 0054, 0059) ────────────────────────
# INSTALL_ENC_PASSPHRASE (preset) → guided manifest → unattended default → tty
# prompt. Every tier but the prompt is unit-testable; the prompt reads /dev/tty,
# so it is stubbed where the fall-through must be observed.

@test "zfs_collect_encryption_passphrase: no-op when encryption off" {
  write_config '{"options":{"encryption":false}}'
  unset INSTALL_ENC_PASSPHRASE GUIDED_SECRETS_MANIFEST
  ZFS_PASSPHRASE="sentinel"
  run zfs_collect_encryption_passphrase
  [ "$status" -eq 0 ]
  # runs in the same shell for the var check
  zfs_collect_encryption_passphrase
  [ "$ZFS_PASSPHRASE" = "sentinel" ]   # untouched — no collection attempted
}

@test "zfs_collect_encryption_passphrase: INSTALL_ENC_PASSPHRASE preset wins" {
  write_config '{"options":{"encryption":true}}'
  export INSTALL_ENC_PASSPHRASE="presetpass"
  export GUIDED_SECRETS_MANIFEST="$TEST_DIR/manifest.json"
  printf '%s\n' '{"enc_passphrase":"guidedpass"}' > "$GUIDED_SECRETS_MANIFEST"
  zfs_collect_encryption_passphrase
  [ "$ZFS_PASSPHRASE" = "presetpass" ]
}

@test "zfs_collect_encryption_passphrase: guided manifest used when no preset" {
  write_config '{"options":{"encryption":true}}'
  unset INSTALL_ENC_PASSPHRASE
  export GUIDED_SECRETS_MANIFEST="$TEST_DIR/manifest.json"
  printf '%s\n' '{"enc_passphrase":"guidedpass"}' > "$GUIDED_SECRETS_MANIFEST"
  zfs_collect_encryption_passphrase
  [ "$ZFS_PASSPHRASE" = "guidedpass" ]
}

@test "zfs_collect_encryption_passphrase: absent manifest passphrase falls to prompt" {
  write_config '{"options":{"encryption":true}}'
  unset INSTALL_ENC_PASSPHRASE INSTALL_UNATTENDED
  export GUIDED_SECRETS_MANIFEST="$TEST_DIR/manifest.json"
  printf '%s\n' '{"root_password":"r00t"}' > "$GUIDED_SECRETS_MANIFEST"
  # stub the tty reader so the fall-through is observable without a terminal.
  prompt_secret() { printf -v "$1" '%s' "prompted"; }
  ZFS_PASSPHRASE=""
  zfs_collect_encryption_passphrase
  [ "$ZFS_PASSPHRASE" = "prompted" ]   # guided tier skipped, prompt reached
}

# ── unattended default tier (ADR 0059) ────────────────────────────────────────
# Below the manifest, above the prompt: an unattended run with nothing else set
# takes the default constant, so `install.sh --profile <encrypted> -y` no longer
# blocks on a tty prompt. Interactive runs (the test above) still prompt.

@test "zfs_collect_encryption_passphrase: unattended default used when no preset/manifest" {
  write_config '{"options":{"encryption":true}}'
  unset INSTALL_ENC_PASSPHRASE GUIDED_SECRETS_MANIFEST
  export INSTALL_UNATTENDED=1
  # a prompt here would mean the tier was skipped — stub it to a sentinel so a
  # regression is visible rather than hanging on /dev/tty.
  prompt_secret() { printf -v "$1" '%s' "SHOULD-NOT-PROMPT"; }
  ZFS_PASSPHRASE=""
  zfs_collect_encryption_passphrase
  [ "$ZFS_PASSPHRASE" = "$INSTALL_DEFAULT_ENC_PASSPHRASE" ]
  [ "$ZFS_PASSPHRASE" = "12345678" ]
}

@test "zfs_collect_encryption_passphrase: manifest beats the unattended default" {
  write_config '{"options":{"encryption":true}}'
  unset INSTALL_ENC_PASSPHRASE
  export INSTALL_UNATTENDED=1
  export GUIDED_SECRETS_MANIFEST="$TEST_DIR/manifest.json"
  printf '%s\n' '{"enc_passphrase":"guidedpass"}' > "$GUIDED_SECRETS_MANIFEST"
  ZFS_PASSPHRASE=""
  zfs_collect_encryption_passphrase
  [ "$ZFS_PASSPHRASE" = "guidedpass" ]
}

@test "default enc passphrase clears ZFS's 8-char keyformat floor" {
  [ "${#INSTALL_DEFAULT_ENC_PASSPHRASE}" -ge 8 ]
}

# ── zfs_ram_gib ───────────────────────────────────────────────────────────────────

@test "zfs_ram_gib: returns a positive integer" {
  run zfs_ram_gib
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}
