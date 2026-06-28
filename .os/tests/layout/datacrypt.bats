#!/usr/bin/env bats
# Tests for the per-group data-encryption emitter (ADR 0043, issue 05) — the
# pure core that, given one data group's encryption decision + filesystem,
# yields the boot-time auto-unlock plan: where the keyfile lives on the
# (already-unlocked) root, the crypttab line for a LUKS group, or the zfs
# key-load options for a zfs group. Only the ROOT is unlocked by the typed
# passphrase; encrypted DATA groups auto-unlock post-boot from a keyfile on the
# root, so no second prompt. Impermanence is out of scope here — the keyfile
# path is constant and the formatter persists /etc/cryptsetup-keys.d via the
# curated persist set. Pure: string transforms, no disk access.

setup() {
  # shellcheck source=../../lib/layout/nonzfs/datacrypt.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/nonzfs/datacrypt.sh"
}

# Helper: extract a key=value field from the emitted plan.
dc_field() { grep -E "^$1=" | cut -d= -f2-; }

# ── tracer: an unencrypted group emits an empty plan (false round-trips) ─────

@test "crypto: encryption=false emits an all-empty plan" {
  run data_group_crypto false ext4 tank ABCD
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dc_field mapper)"      = "" ]
  [ "$(printf '%s\n' "$output" | dc_field keyfile)"     = "" ]
  [ "$(printf '%s\n' "$output" | dc_field crypttab)"    = "" ]
  [ "$(printf '%s\n' "$output" | dc_field zfs_keyload)" = "" ]
}

# ── encrypted LUKS group (ext4): keyfile on root + crypttab auto-open ────────

@test "crypto: encrypted ext4 emits keyfile + mapper + crypttab, no zfs load" {
  run data_group_crypto true ext4 tank ABCD
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dc_field mapper)"  = "crypttank" ]
  [ "$(printf '%s\n' "$output" | dc_field keyfile)" \
      = "/etc/cryptsetup-keys.d/tank.key" ]
  [ "$(printf '%s\n' "$output" | dc_field crypttab)" \
      = "crypttank  UUID=ABCD  /etc/cryptsetup-keys.d/tank.key  luks" ]
  [ "$(printf '%s\n' "$output" | dc_field zfs_keyload)" = "" ]
}

# Every non-zfs filesystem is LUKS (PRD): btrfs takes the crypttab path, not the
# zfs key-load path.
@test "crypto: encrypted btrfs is LUKS (crypttab, not zfs_keyload)" {
  run data_group_crypto true btrfs vault FEED
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dc_field crypttab)" \
      = "cryptvault  UUID=FEED  /etc/cryptsetup-keys.d/vault.key  luks" ]
  [ "$(printf '%s\n' "$output" | dc_field zfs_keyload)" = "" ]
}

# ── encrypted zfs group: key-load options on the pool, no crypttab/mapper ────

@test "crypto: encrypted zfs emits zfs_keyload + keyfile, no crypttab/mapper" {
  run data_group_crypto true zfs tank UNUSED
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dc_field keyfile)" \
      = "/etc/cryptsetup-keys.d/tank.key" ]
  [ "$(printf '%s\n' "$output" | dc_field zfs_keyload)" \
      = "-O encryption=aes-256-gcm -O keyformat=raw -O keylocation=file:///etc/cryptsetup-keys.d/tank.key" ]
  [ "$(printf '%s\n' "$output" | dc_field mapper)"   = "" ]
  [ "$(printf '%s\n' "$output" | dc_field crypttab)" = "" ]
}
