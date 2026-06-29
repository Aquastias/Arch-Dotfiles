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
# Data Group Formatter (lib/layout/<fs>/data.sh) as `_data_mkfs`, which this
# core calls. The per-fs file sources this core.
#
# Pure cores (unit-tested): data_group_fstab_line. The orchestration
# (data_group_create) is disk-touching and VM-gated, like the ZFS data-pool
# path. Requires at call time: lib/common.sh (info/section/error), MOUNT_ROOT,
# and the per-fs `_data_mkfs`.
# =============================================================================

# The per-group encryption plan emitter (keyfile/mapper/crypttab) — sibling.
# shellcheck source=./datacrypt.sh
source "${BASH_SOURCE[0]%/*}/datacrypt.sh"

# The /etc/fstab line a formatted data group contributes. <src> is the mount
# source: `UUID=<fs-uuid>` for a plaintext group, or `/dev/mapper/crypt<name>`
# for an encrypted one (crypttab opens the mapper from the keyfile first). pass
# 2 = fsck after the root. Pure: a string transform.
data_group_fstab_line() {
  local src="$1" mount="$2" fs="$3"
  printf '%s  %s  %s  defaults  0 2\n' "$src" "$mount" "$fs"
}

# Pull one key=value field out of a datacrypt plan on stdin.
_data_plan_field() { grep -E "^$1=" | cut -d= -f2-; }

# The dm-crypt mapper name for device <index> of a <total>-device encrypted data
# group. A single-disk group keeps the bare crypt<name> (matching datacrypt's
# single mapper — the verified path); a multi-disk group (only btrfs reaches >1,
# the others are single-disk by validation) suffixes the index so its raid
# assembles over distinct mappers crypt<name>0, crypt<name>1, …. Pure.
data_group_mapper_name() {
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
_data_gen_keyfile() {
  local abs="$1"
  install -Dm600 /dev/null "$abs"
  head -c32 /dev/urandom >"$abs"
}

# Disk-touching: format + mount one non-ZFS data group, appending its fstab and
# (encrypted) crypttab lines to the layout record the chroot writers consume.
#   data_group_create <fs> <name> <encrypted> <mount> <topology> <part...>
# Plaintext groups mount by filesystem UUID. Encrypted groups are single-disk:
# the partition is LUKS-formatted with the keyfile-on-root, opened as
# crypt<name>, and the fs lives inside the mapper. btrfs may span several parts
# with native topology (plaintext only this slice). Calls the per-fs _data_mkfs.
# VM-gated, like the ZFS data-pool path.
data_group_create() {
  local fs="$1" name="$2" encrypted="$3" mount="$4" topology="$5"
  shift 5
  local parts=("$@")
  local nl=$'\n'
  section "Formatting Data Group '${name}' (${fs})"

  # The live ISO ships the mkfs tools but may not have the fs kernel module
  # loaded, so the freshly-formatted fs can't be mounted here without it (ext4
  # is built-in; xfs/btrfs are modules). Load it; harmless if built-in/loaded.
  modprobe "$fs" 2>/dev/null || true

  local target src
  local mkfs_inputs=()
  if [[ "$encrypted" == "true" && ${#parts[@]} -eq 1 ]]; then
    # ── single-disk encrypted (ext4/xfs/btrfs) — the verified path ──
    # keyfile path + mapper name are UUID-independent — read them up front so we
    # can format/open before the LUKS container UUID exists.
    local plan keyfile mapper
    plan="$(data_group_crypto true "$fs" "$name" PENDING)"
    keyfile="$(printf '%s\n' "$plan" | _data_plan_field keyfile)"
    mapper="$(printf '%s\n' "$plan" | _data_plan_field mapper)"

    _data_gen_keyfile "${MOUNT_ROOT}${keyfile}"
    cryptsetup luksFormat --type luks2 --batch-mode \
      "${parts[0]}" "${MOUNT_ROOT}${keyfile}"
    cryptsetup open "${parts[0]}" "$mapper" \
      --key-file "${MOUNT_ROOT}${keyfile}"
    target="/dev/mapper/${mapper}"
    src="$target"
    mkfs_inputs=("$target")

    local uuid crypttab
    uuid="$(blkid -s UUID -o value "${parts[0]}")" # LUKS container UUID
    crypttab="$(data_group_crypto true "$fs" "$name" "$uuid" \
      | _data_plan_field crypttab)"
    LAYOUT_CRYPTTAB="${LAYOUT_CRYPTTAB:+${LAYOUT_CRYPTTAB}${nl}}${crypttab}"
  elif [[ "$encrypted" == "true" ]]; then
    # ── multi-disk encrypted (btrfs raid over per-device LUKS mappers) ──
    # ext4/xfs are single-disk by validation, so only a btrfs group lands here.
    # One keyfile-on-root opens every device; each is wrapped as crypt<name><i>
    # and the raid is built over the mappers. crypttab auto-opens each at boot.
    [[ "$fs" == "btrfs" ]] \
      || error "Encrypted multi-disk data group '${name}' needs btrfs (got ${fs})."
    local keyfile i part mapper uuid crypttab
    keyfile="$(data_group_crypto true "$fs" "$name" PENDING \
      | _data_plan_field keyfile)"
    _data_gen_keyfile "${MOUNT_ROOT}${keyfile}"
    for i in "${!parts[@]}"; do
      part="${parts[$i]}"
      mapper="$(data_group_mapper_name "$name" "$i" "${#parts[@]}")"
      cryptsetup luksFormat --type luks2 --batch-mode \
        "$part" "${MOUNT_ROOT}${keyfile}"
      cryptsetup open "$part" "$mapper" --key-file "${MOUNT_ROOT}${keyfile}"
      mkfs_inputs+=("/dev/mapper/${mapper}")
      uuid="$(blkid -s UUID -o value "$part")" # LUKS container UUID
      crypttab="${mapper}  UUID=${uuid}  ${keyfile}  luks"
      LAYOUT_CRYPTTAB="${LAYOUT_CRYPTTAB:+${LAYOUT_CRYPTTAB}${nl}}${crypttab}"
    done
    target="${mkfs_inputs[0]}"
  else
    # ── plaintext (single or multi-disk) ──
    target="${parts[0]}"
    mkfs_inputs=("${parts[@]}")
  fi

  _DATA_TOPOLOGY="$topology"
  _data_mkfs "${mkfs_inputs[@]}"

  mkdir -p "${MOUNT_ROOT}${mount}"
  mount "$target" "${MOUNT_ROOT}${mount}"

  # A multi-disk btrfs (plaintext or encrypted) mounts by its single fs UUID;
  # single-disk encrypted keeps its mapper src (set above, verified).
  if [[ -z "${src:-}" ]]; then
    src="UUID=$(blkid -s UUID -o value "$target")"
  fi
  local fstab
  fstab="$(data_group_fstab_line "$src" "$mount" "$fs")"
  LAYOUT_FSTAB_EXTRA="${LAYOUT_FSTAB_EXTRA:+${LAYOUT_FSTAB_EXTRA}${nl}}${fstab}"
  info "Data group '${name}' formatted → ${mount} (${fs})"
}
