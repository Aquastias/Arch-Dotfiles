#!/usr/bin/env bats
# Tests for the non-ZFS Data Group Formatter core (ADR 0043, issue 05) — the
# pure bits under the ext4/xfs/btrfs Data Group Formatters. The disk-touching
# orchestration (mkfs/luksFormat/mount) is VM-gated; the fstab line a formatted
# data group contributes is pure and tested here. A plaintext group mounts by
# filesystem UUID; an encrypted group mounts the dm-crypt mapper (the crypttab
# opens it from the keyfile). Pure: string transforms, no disk access.

setup() {
  # shellcheck source=../../lib/layout/nonzfs/data.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/nonzfs/data.sh"
}

# ── plaintext: mount by filesystem UUID ──────────────────────────────────────

@test "fstab: a plaintext data group mounts by UUID at its mount" {
  run data_group_fstab_line "UUID=DEAD-BEEF" /srv/tank ext4
  [ "$status" -eq 0 ]
  [ "$output" = "UUID=DEAD-BEEF  /srv/tank  ext4  defaults  0 2" ]
}

# ── encrypted: mount the dm-crypt mapper (crypttab opened it from the keyfile)

@test "fstab: an encrypted data group mounts its mapper" {
  run data_group_fstab_line /dev/mapper/crypttank /srv/tank xfs
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/mapper/crypttank  /srv/tank  xfs  defaults  0 2" ]
}

# ── per-device dm-crypt mapper naming (encrypted multi-disk btrfs, ADR 0043) ──
# A single-disk group keeps the bare crypt<name> (the verified path); a multi-
# disk group (only btrfs reaches >1) suffixes the device index so its raid
# assembles over distinct mappers crypt<name>0, crypt<name>1, ….

@test "mapper-name: a single-disk group uses the bare crypt<name>" {
  run data_group_mapper_name tank 0 1
  [ "$status" -eq 0 ]
  [ "$output" = "crypttank" ]
}

@test "mapper-name: a multi-disk group suffixes the device index" {
  run data_group_mapper_name tank 0 2
  [ "$output" = "crypttank0" ]
  run data_group_mapper_name tank 1 2
  [ "$output" = "crypttank1" ]
}
