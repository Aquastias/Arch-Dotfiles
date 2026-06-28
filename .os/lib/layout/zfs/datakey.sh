#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/datakey.sh — standalone-ZFS-data-pool key-load selector (0043)
# =============================================================================
# The pure seam create_data_pools consumes to encrypt a Standalone Data Pool.
# Only the ROOT is unlocked by the typed passphrase; an encrypted DATA pool
# auto-loads its key POST-boot from a keyfile stored on the (already-unlocked)
# root — so the operator types one secret per boot, never a second prompt for
# the data pool. This module projects the zfs branch of the shared per-group
# crypto plan (lib/layout/nonzfs/datacrypt.sh) into the two things the pool
# create needs:
#   - keyfile — where the 32-byte raw key lives on the root, which the caller
#               must generate before `zpool create`.
#   - opts    — the `-O encryption/keyformat/keylocation` tokens for the create,
#               replacing the global passphrase-prompt ENC_OPTS for this pool.
# A plaintext pool selects an empty keyfile + empty opts (the `false` decision
# round-trips — the pool is created unencrypted).
#
# Pure: string transforms on its arguments, no disk access.
#
# Public API:
#   zfs_data_pool_enc_opts <encrypted> <name>
#     <encrypted>  true|false — the pool's per-group encryption decision.
#     <name>       the pool name (keyfile filename).
#     → emits `keyfile=<path>` then `opts=<tokens>` (each empty when plaintext).
# =============================================================================

# The shared per-group crypto plan emitter — sibling under nonzfs/.
# shellcheck source=../nonzfs/datacrypt.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/datacrypt.sh"

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
