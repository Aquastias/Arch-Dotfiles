#!/usr/bin/env bats
# Tests for the standalone-ZFS-data-pool encryption-opts selector (ADR 0043,
# issue 05). The pure seam create_data_pools consumes so an encrypted data pool
# auto-loads its key POST-boot from a keyfile on the (already-unlocked) root —
# never re-prompting for the boot passphrase. A plaintext pool selects nothing
# (the `false` round-trips). Delegates the plan to data_group_crypto; this layer
# just projects the zfs branch into (keyfile, opts) the pool create needs.
# Pure: string transforms, no disk access.

setup() {
  # shellcheck source=../../lib/layout/zfs/datakey.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/zfs/datakey.sh"
}

dk_field() { grep -E "^$1=" | cut -d= -f2-; }

# ── tracer: a plaintext pool selects no keyfile + no opts (false round-trips) ─

@test "data-pool enc-opts: plaintext selects empty keyfile + empty opts" {
  run zfs_data_pool_enc_opts false tank0
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dk_field keyfile)" = "" ]
  [ "$(printf '%s\n' "$output" | dk_field opts)"    = "" ]
}

# ── encrypted pool: keyfile on root + raw-key file:// load, never a prompt ────

@test "data-pool enc-opts: encrypted selects keyfile-on-root + file:// opts" {
  run zfs_data_pool_enc_opts true tank0
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | dk_field keyfile)" \
      = "/etc/cryptsetup-keys.d/tank0.key" ]
  [ "$(printf '%s\n' "$output" | dk_field opts)" \
      = "-O encryption=aes-256-gcm -O keyformat=raw -O keylocation=file:///etc/cryptsetup-keys.d/tank0.key" ]
}

# The selected opts must never re-prompt for the boot passphrase — the whole
# point of the keyfile-on-root model is one secret per boot.
@test "data-pool enc-opts: encrypted opts never use keylocation=prompt" {
  run zfs_data_pool_enc_opts true vault
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | dk_field opts)" != *"keylocation=prompt"* ]]
}
