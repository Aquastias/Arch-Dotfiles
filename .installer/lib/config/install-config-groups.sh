#!/usr/bin/env bash
# =============================================================================
# lib/config/install-config-groups.sh — Install Config Reader: per-group fields
# =============================================================================
# The Install Config Reader's per-group half (ADR 0043): Storage Group and
# Data Pool accessors, the Manual Partitioning assignment (ADR 0073), and the
# derived any-group predicates (any-ZFS, any-LUKS, uses-filesystem). Split
# from install-config.sh for size; kept on `install_config_` by a `file` rule.
#
# Sourced by: lib/config/install-config.sh (never directly).
# =============================================================================

install_config_storage_group_ashift() {
  local value; value="$(_install_config_optional ".storage_groups[$1].ashift")"
  printf '%s\n' "${value:-12}"
}

# Number of declared storage_groups[] entries (0 when absent).
install_config_storage_groups_count() {
  _install_config_read '(.storage_groups // []) | length'
}

# Storage Group name at index — emitted raw.
install_config_storage_group_name() {
  _install_config_optional ".storage_groups[$1].name"
}

# Per-group filesystem (ADR 0043) — like the data_pool reader; absent inherits
# the root `filesystem`.
install_config_storage_group_filesystem() {
  local value
  value="$(_install_config_optional ".storage_groups[$1].filesystem")"
  printf '%s\n' "${value:-$(install_config_filesystem)}"
}

# Per-group encryption (ADR 0043) — independent bool, default false; explicit
# null check so a stored `false` round-trips (jq gotcha).
install_config_storage_group_encryption() {
  local value
  value="$(_install_config_read ".storage_groups[$1].encryption")"
  [[ "$value" == "true" ]] && printf 'true\n' || printf 'false\n'
}

# Owners access list (pool-owners, ADR 0031) — one token per line, in order; a
# bare token is a user, an @-prefixed token a group. Empty when absent. Defined
# for both pool kinds; the Owners Resolver decides chown vs ACL from the tokens.
install_config_storage_group_owners() {
  _install_config_read ".storage_groups[$1].owners[]?"
}

install_config_data_pool_owners() {
  _install_config_read ".data_pools[$1].owners[]?"
}

# =============================================================================
# Standalone Data Pools — data_pools[] accessors (ADR 0027)
# =============================================================================
# Each entry becomes its own zpool. name + disks are required (read raw);
# topology, mount, ashift carry defaults. Indexed like the storage-group
# ashift special above.

# Number of declared data_pools[] entries (0 when absent).
install_config_data_pools_count() {
  _install_config_read '(.data_pools // []) | length'
}

# Pool name at index — the literal zpool name. Emitted raw.
install_config_data_pool_name() {
  _install_config_optional ".data_pools[$1].name"
}

# Topology at index — defaults to 'stripe'.
install_config_data_pool_topology() {
  local value; value="$(_install_config_optional ".data_pools[$1].topology")"
  printf '%s\n' "${value:-stripe}"
}

# Mountpoint at index — defaults to /data/<name>.
install_config_data_pool_mount() {
  local value; value="$(_install_config_optional ".data_pools[$1].mount")"
  if [[ -z "$value" ]]; then
    value="/data/$(install_config_data_pool_name "$1")"
  fi
  printf '%s\n' "$value"
}

# Ashift at index — defaults to 12.
install_config_data_pool_ashift() {
  local value; value="$(_install_config_optional ".data_pools[$1].ashift")"
  printf '%s\n' "${value:-12}"
}

# Disks at index — one device path per line.
install_config_data_pool_disks() {
  _install_config_read ".data_pools[$1].disks[]?"
}

# Per-group filesystem (ADR 0043) — a Standalone Data Pool may pick its own
# filesystem; absent inherits the root `filesystem`. An explicit value wins.
install_config_data_pool_filesystem() {
  local value; value="$(_install_config_optional ".data_pools[$1].filesystem")"
  printf '%s\n' "${value:-$(install_config_filesystem)}"
}

# Per-group encryption (ADR 0043) — an independent bool, default false. Read raw
# with an explicit null check so a stored `false` round-trips (a `// false`
# default cannot distinguish absent from an explicit false — jq gotcha).
install_config_data_pool_encryption() {
  local value; value="$(_install_config_read ".data_pools[$1].encryption")"
  [[ "$value" == "true" ]] && printf 'true\n' || printf 'false\n'
}

# Any-ZFS predicate (ADR 0043) — `true` when the root OR any data pool / storage
# group resolves to zfs. Gates zfs userland, boot-time import, the ZFS Module
# Guard, and the archzfs-compatible ISO: a machine with no zfs group anywhere
# needs none of them; an ext4 root + zfs data pool still does. Each per-group
# accessor inherits the root filesystem when the group omits its own.
install_config_any_zfs() {
  # Manual Partitioning (ADR 0073) is always poolless plain partitions — the
  # `filesystem` field is locked/ignored, so a manual install never needs the
  # ZFS userland, boot-time import, or module guard even though filesystem
  # still defaults to zfs.
  [[ "$(install_config_disk_kind)" == "manual" ]] \
    && { printf 'false\n'; return; }
  [[ "$(install_config_filesystem)" == "zfs" ]] && { printf 'true\n'; return; }
  local count i
  count="$(install_config_data_pools_count)"
  for ((i = 0; i < count; i++)); do
    [[ "$(install_config_data_pool_filesystem "$i")" == "zfs" ]] \
      && { printf 'true\n'; return; }
  done
  count="$(install_config_storage_groups_count)"
  for ((i = 0; i < count; i++)); do
    [[ "$(install_config_storage_group_filesystem "$i")" == "zfs" ]] \
      && { printf 'true\n'; return; }
  done
  printf 'false\n'
}

# ── Manual Partitioning — disk_config.partitions[] accessors (ADR 0073) ──────
# The flat, operator-authored partition assignment consumed by the manual Root
# Layout Adapter when `disk_kind` is `manual`. Each entry carries the device,
# the mountpoint (/, /boot/efi, /home, [swap], or empty=ignored), the filesystem
# to mkfs, and whether to format (vs keep existing data).

# Number of declared partitions[] entries (0 when absent).
install_config_partitions_count() {
  _install_config_read '(.disk_config.partitions // []) | length'
}

# Whole partitions[] array as compact JSON (the planner input; [] when absent).
install_config_partitions_json() {
  _install_config_read '(.disk_config.partitions // []) | tojson'
}

# Per-partition fields at index — emitted raw.
install_config_partition_device() {
  _install_config_optional ".disk_config.partitions[$1].device"
}
install_config_partition_mountpoint() {
  _install_config_optional ".disk_config.partitions[$1].mountpoint"
}
install_config_partition_filesystem() {
  _install_config_optional ".disk_config.partitions[$1].fs"
}

# Format flag — true unless explicitly false (a kept/reused partition).
install_config_partition_format() {
  local value
  value="$(_install_config_read ".disk_config.partitions[$1].format")"
  [[ "$value" == "false" ]] && { printf 'false\n'; return; }
  printf 'true\n'
}

# Any-LUKS predicate (ADR 0043) — `true` when the root OR any data pool is a
# non-zfs ENCRYPTED group (zfs uses native crypto, never LUKS). Gates cryptsetup
# userland + the boot-time crypttab: a zfs root with an encrypted ext4 data disk
# still needs them even though the root is unencrypted. (Storage groups are
# zfs-only by validation, so they never contribute LUKS.)
install_config_any_nonzfs_luks() {
  [[ "$(install_config_filesystem)" != "zfs" \
     && "$(install_config_encryption_enabled)" == "true" ]] \
    && { printf 'true\n'; return; }
  local count i
  count="$(install_config_data_pools_count)"
  for ((i = 0; i < count; i++)); do
    [[ "$(install_config_data_pool_filesystem "$i")" != "zfs" \
       && "$(install_config_data_pool_encryption "$i")" == "true" ]] \
      && { printf 'true\n'; return; }
  done
  printf 'false\n'
}

# Filesystem-use predicate (ADR 0043) — `true` when the root OR any data pool /
# storage group resolves to <fs>. Gates the per-filesystem mkfs/fsck userland on
# the target (xfsprogs for xfs, btrfs-progs for btrfs): a machine that uses the
# filesystem anywhere needs its tools so the group fscks/mounts at boot. Each
# per-group accessor inherits the root filesystem when the group omits its own.
install_config_uses_filesystem() {
  local filesystem="$1"
  [[ "$(install_config_filesystem)" == "$filesystem" ]] \
    && { printf 'true\n'; return; }
  local count i
  count="$(install_config_data_pools_count)"
  for ((i = 0; i < count; i++)); do
    [[ "$(install_config_data_pool_filesystem "$i")" == "$filesystem" ]] \
      && { printf 'true\n'; return; }
  done
  count="$(install_config_storage_groups_count)"
  for ((i = 0; i < count; i++)); do
    [[ "$(install_config_storage_group_filesystem "$i")" == "$filesystem" ]] \
      && { printf 'true\n'; return; }
  done
  printf 'false\n'
}
