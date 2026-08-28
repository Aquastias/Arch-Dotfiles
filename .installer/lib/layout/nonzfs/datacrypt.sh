#!/usr/bin/env bash
# =============================================================================
# lib/layout/nonzfs/datacrypt.sh — per-group data-encryption emitter (ADR 0043)
# =============================================================================
# The pure core under the Data Group Formatters' per-group encryption. Only the
# ROOT is unlocked by the typed passphrase (initramfs); encrypted DATA groups
# auto-unlock POST-boot from a keyfile stored on the already-unlocked root — so
# the operator types one secret per boot. This module decides, for one data
# group, the auto-unlock plan the formatter realizes:
#   - keyfile      — where the unlock keyfile lives on the root, the canonical
#                    /etc/cryptsetup-keys.d/<name>.key (a single 32-byte random
#                    keyfile serves LUKS keyslots AND zfs keyformat=raw).
#   - mapper       — the dm-crypt name for a LUKS group (empty for zfs).
#   - crypttab     — the /etc/crypttab line that auto-opens a LUKS group.
#   - zfs_keyload  — the `zpool create` key options for a zfs group.
# An unencrypted group yields an all-empty plan (the `false` decision round-
# trips — the formatter then just mounts the bare device).
#
# Impermanence is NOT this module's concern: the keyfile path is constant on/off.
# Under root impermanence the formatter persists /etc/cryptsetup-keys.d via the
# curated persist set (a CURATED_DIRS entry, exactly like the /etc/secrets SOPS
# key), so it survives the boot-time rollback without touching crypttab.
#
# Pure: string transforms on its arguments, no disk access.
#
# Public API:
#   data_group_crypto <encrypted> <fs> <name> <uuid>
#     <encrypted>  true|false — the group's per-group encryption decision.
#     <fs>         the group's filesystem (zfs → key-load; else → crypttab).
#     <name>       the group name (keyfile filename + mapper name).
#     <uuid>       the LUKS container UUID (crypttab reference); unused by zfs.
#     → emits a `key=value` plan on stdout: mapper, keyfile, crypttab,
#       zfs_keyload (each empty when not applicable).
# =============================================================================

data_group_crypto() {
  local encrypted="$1" fs="$2" name="$3" uuid="$4"

  local mapper="" keyfile="" crypttab="" zfs_keyload=""

  if [[ "$encrypted" == "true" ]]; then
    keyfile="/etc/cryptsetup-keys.d/${name}.key"
    if [[ "$fs" == "zfs" ]]; then
      # zfs is natively encrypted: the pool loads its raw key from the keyfile
      # (no dm-crypt mapper, no crypttab). Cipher matches the root pool's
      # build_enc_opts (aes-256-gcm).
      zfs_keyload="-O encryption=aes-256-gcm -O keyformat=raw"
      zfs_keyload+=" -O keylocation=file://${keyfile}"
    else
      # A LUKS group auto-opens via crypttab; the dm-crypt mapper is named for
      # the group so several encrypted groups never collide.
      mapper="crypt${name}"
      crypttab="${mapper}  UUID=${uuid}  ${keyfile}  luks"
    fi
  fi

  printf 'mapper=%s\n'      "$mapper"
  printf 'keyfile=%s\n'     "$keyfile"
  printf 'crypttab=%s\n'    "$crypttab"
  printf 'zfs_keyload=%s\n' "$zfs_keyload"
}
