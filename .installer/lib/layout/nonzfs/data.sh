#!/usr/bin/env bash
# =============================================================================
# lib/layout/nonzfs/data.sh — non-ZFS Data Group Formatter core (ADR 0043)
# =============================================================================
# The shared spine under the ext4/xfs/btrfs Data Group Formatters. A non-ZFS
# data group is a plain disk (ESP-less): one GPT partition, optionally LUKS-
# wrapped, formatted with the group's filesystem and mounted at its declared
# mount under the install root. Encryption reuses the keyfile-on-root model
# (lib/layout/nonzfs/datacrypt.sh): the group's 32-byte keyfile lives on the
# already-unlocked root and a crypttab entry auto-opens it post-boot, so the
# operator types one secret per boot.
#
# The filesystem-specific bit — the mkfs command — is supplied by the per-fs
# Data Group Formatter (lib/layout/<fs>/data.sh) as `data_formatter_mkfs`, which this
# core calls. The per-fs file sources this core.
#
# Pure cores (unit-tested): layout_data_group_fstab_line. The orchestration
# (data_formatter_create_group) is disk-touching and VM-gated, like the ZFS data-pool
# path. Requires at call time: lib/common.sh (info/section/error), MOUNT_ROOT,
# and the per-fs `data_formatter_mkfs`.
# =============================================================================

# The per-group encryption plan emitter (keyfile/mapper/crypttab) — sibling.
# shellcheck source=./datacrypt.sh
source "${BASH_SOURCE[0]%/*}/datacrypt.sh"
# The shared `key=value` plan-field reader (layout_plan_field) lives in the
# layout core; guard-source it so this formatter stands alone in its unit test.
declare -F layout_plan_field >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../core.sh"

# The /etc/fstab line a formatted data group contributes. <src> is the mount
# source: `UUID=<fs-uuid>` for a plaintext group, or `/dev/mapper/crypt<name>`
# for an encrypted one (crypttab opens the mapper from the keyfile first). pass
# 2 = fsck after the root. Pure: a string transform.
layout_data_group_fstab_line() {
  local source_device="$1" mount="$2" filesystem="$3"
  printf '%s  %s  %s  defaults  0 2\n' "$source_device" "$mount" "$filesystem"
}


# The dm-crypt mapper name for device <index> of a <total>-device encrypted data
# group. A single-disk group keeps the bare crypt<name> (matching datacrypt's
# single mapper — the verified path); a multi-disk group (only btrfs reaches >1,
# the others are single-disk by validation) suffixes the index so its raid
# assembles over distinct mappers crypt<name>0, crypt<name>1, …. Pure.
layout_data_group_mapper_name() {
  local name="$1" index="$2" total="$3"
  if ((total > 1)); then
    printf 'crypt%s%s\n' "$name" "$index"
  else
    printf 'crypt%s\n' "$name"
  fi
}

# Generate the group's 32-byte random keyfile at $abs (under the install root)
# with 0600 perms. One primitive for every filesystem: LUKS takes it as a
# keyslot, zfs as keyformat=raw.
_nonzfs_data_generate_keyfile() {
  local abs="$1"
  install -Dm600 /dev/null "$abs"
  dd if=/dev/urandom bs=32 count=1 status=none >"$abs"
}

# Disk-touching: format + mount one non-ZFS data group, appending its fstab and
# (encrypted) crypttab lines to the layout record the chroot writers consume.
#   data_formatter_create_group <fs> <name> <encrypted> <mount> <topology> <part...>
# Plaintext groups mount by filesystem UUID. Encrypted groups are single-disk:
# the partition is LUKS-formatted with the keyfile-on-root, opened as
# crypt<name>, and the fs lives inside the mapper. btrfs may span several parts
# with native topology (plaintext only this slice). Calls the per-fs data_formatter_mkfs.
# VM-gated, like the ZFS data-pool path.
data_formatter_create_group() {
  local filesystem="$1" name="$2" encrypted="$3" mount="$4" topology="$5"
  shift 5
  local parts=("$@")
  section "Formatting Data Group '${name}' (${filesystem})"

  # The live ISO ships the mkfs tools but may not have the fs kernel module
  # loaded, so the freshly-formatted fs can't be mounted here without it (ext4
  # is built-in; xfs/btrfs are modules). Load it; harmless if built-in/loaded.
  modprobe "$filesystem" 2>/dev/null || true

  # Set by the branch below: the device to mount, its fstab source (empty →
  # mount by fs UUID), and the device(s) mkfs formats.
  local target source_device="" mkfs_inputs=()
  if [[ "$encrypted" == "true" && ${#parts[@]} -eq 1 ]]; then
    _nonzfs_data_open_single_encrypted "$filesystem" "$name" "${parts[0]}"
  elif [[ "$encrypted" == "true" ]]; then
    _nonzfs_data_open_multi_encrypted "$filesystem" "$name" "${parts[@]}"
  else
    # ── plaintext (single or multi-disk) ──
    target="${parts[0]}"
    mkfs_inputs=("${parts[@]}")
  fi

  _DATA_TOPOLOGY="$topology"
  data_formatter_mkfs "${mkfs_inputs[@]}"

  mkdir -p "${MOUNT_ROOT}${mount}"
  mount "$target" "${MOUNT_ROOT}${mount}"

  # A multi-disk btrfs (plaintext or encrypted) mounts by its single fs UUID;
  # single-disk encrypted keeps its mapper src (set above, verified).
  if [[ -z "${source_device:-}" ]]; then
    source_device="UUID=$(blkid -s UUID -o value "$target")"
  fi
  _nonzfs_data_append_line LAYOUT_FSTAB_EXTRA \
    "$(layout_data_group_fstab_line "$source_device" "$mount" "$filesystem")"
  info "Data group '${name}' formatted → ${mount} (${filesystem})"
}

# _nonzfs_data_append_line <variable> <line> — append a line to a
# newline-separated layout record (LAYOUT_CRYPTTAB, LAYOUT_FSTAB_EXTRA).
_nonzfs_data_append_line() {
  local -n __record="$1"
  __record="${__record:+${__record}$'\n'}$2"
}

# ── single-disk encrypted (ext4/xfs/btrfs) — the verified path ──
# Sets the caller's target, source_device and mkfs_inputs to the opened
# mapper. Keyfile path + mapper name are UUID-independent — read them up
# front so we can format/open before the LUKS container UUID exists.
_nonzfs_data_open_single_encrypted() {
  local filesystem="$1" name="$2" partition="$3" plan keyfile mapper uuid
  plan="$(layout_data_group_crypto true "$filesystem" "$name" PENDING)"
  keyfile="$(printf '%s\n' "$plan" | layout_plan_field keyfile)"
  mapper="$(printf '%s\n' "$plan" | layout_plan_field mapper)"

  _nonzfs_data_generate_keyfile "${MOUNT_ROOT}${keyfile}"
  cryptsetup luksFormat --type luks2 --batch-mode \
    "$partition" "${MOUNT_ROOT}${keyfile}"
  cryptsetup open "$partition" "$mapper" \
    --key-file "${MOUNT_ROOT}${keyfile}"
  target="/dev/mapper/${mapper}"
  source_device="$target"
  mkfs_inputs=("$target")

  uuid="$(blkid -s UUID -o value "$partition")" # LUKS container UUID
  _nonzfs_data_append_line LAYOUT_CRYPTTAB \
    "$(layout_data_group_crypto true "$filesystem" "$name" "$uuid" \
       | layout_plan_field crypttab)"
}

# ── multi-disk encrypted (btrfs raid over per-device LUKS mappers) ──
# ext4/xfs are single-disk by validation, so only a btrfs group lands here.
# One keyfile-on-root opens every device; each is wrapped as crypt<name><i>
# and the raid is built over the mappers. crypttab auto-opens each at boot.
# Sets the caller's target and mkfs_inputs.
_nonzfs_data_open_multi_encrypted() {
  local filesystem="$1" name="$2"
  shift 2
  local parts=("$@") keyfile i part mapper uuid
  [[ "$filesystem" == "btrfs" ]] \
    || error "Encrypted multi-disk data group '${name}' needs btrfs" \
             "(got ${filesystem})."
  keyfile="$(layout_data_group_crypto true "$filesystem" "$name" PENDING \
    | layout_plan_field keyfile)"
  _nonzfs_data_generate_keyfile "${MOUNT_ROOT}${keyfile}"
  for i in "${!parts[@]}"; do
    part="${parts[$i]}"
    mapper="$(layout_data_group_mapper_name "$name" "$i" "${#parts[@]}")"
    cryptsetup luksFormat --type luks2 --batch-mode \
      "$part" "${MOUNT_ROOT}${keyfile}"
    cryptsetup open "$part" "$mapper" --key-file "${MOUNT_ROOT}${keyfile}"
    mkfs_inputs+=("/dev/mapper/${mapper}")
    uuid="$(blkid -s UUID -o value "$part")" # LUKS container UUID
    _nonzfs_data_append_line LAYOUT_CRYPTTAB \
      "${mapper}  UUID=${uuid}  ${keyfile}  luks"
  done
  target="${mkfs_inputs[0]}"
}
