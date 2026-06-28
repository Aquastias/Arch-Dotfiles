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
