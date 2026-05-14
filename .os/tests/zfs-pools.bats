#!/usr/bin/env bats
# Tests for .os/lib/zfs-pools.sh — ZFS pool primitives.
# Covers: build_vdev_spec (pure), build_enc_opts (config-driven), ram_gib.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  # shellcheck source=../lib/zfs-pools.sh
  source "$BATS_TEST_DIRNAME/../lib/zfs-pools.sh"
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

@test "build_vdev_spec: independent emits all parts space-separated (same as stripe)" {
  run build_vdev_spec independent /dev/sda1 /dev/sdb1
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda1 /dev/sdb1" ]
}

@test "build_vdev_spec: unknown topology exits non-zero" {
  run build_vdev_spec bogus /dev/sda1
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

@test "build_enc_opts: encryption true → ENC_OPTS includes keyformat=passphrase" {
  write_config '{"options": {"encryption": "true"}}'
  build_enc_opts
  [[ "${ENC_OPTS[*]}" == *"keyformat=passphrase"* ]]
}

@test "build_enc_opts: missing encryption field defaults to false → ENC_OPTS empty" {
  write_config '{}'
  build_enc_opts
  [ "${#ENC_OPTS[@]}" -eq 0 ]
}

# ── ram_gib ───────────────────────────────────────────────────────────────────

@test "ram_gib: returns a positive integer" {
  run ram_gib
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}
