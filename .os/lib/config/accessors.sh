#!/usr/bin/env bash
# =============================================================================
# lib/config/accessors.sh — Install Config Reader (typed accessors)
# =============================================================================
# Sole owner of Install Config schema defaults. The schema below is the
# canonical declaration of every regular Install Config field: jq path, type
# and default value. The `install_config_<name>` wrappers are generated from
# this schema at source time and forward to `install_config_get`.
#
# To find where a regular accessor is defined, grep this file for the schema
# row — that is the declaration site. The hand-written specials below the
# schema (notably Kernel Selection) each break the schema mould.
#
# Sourced by 03-install.sh after lib/common.sh (which provides cfgo).
# =============================================================================

# shellcheck source=../common.sh
[[ "$(type -t cfgo)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../common.sh"

# shellcheck source=../packages/kernel.sh
[[ "$(type -t kernel_is_valid_token)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../packages/kernel.sh"

# Schema rows: name|jq_path|type|default
# Type ∈ {scalar, bool, array}. Empty default = emit empty when absent.
_INSTALL_CONFIG_SCHEMA=(
  "bootloader|.options.bootloader|scalar|systemd-boot"
  "swap_enabled|.options.swap|bool|true"
  "zswap_enabled|.options.zswap.enabled|bool|true"
  "zswap_compressor|.options.zswap.compressor|scalar|zstd"
  "zswap_max_pool_percent|.options.zswap.max_pool_percent|scalar|20"
  "esp_size|.options.esp_size|scalar|2G"
  "root_shell|.options.root_shell|scalar|/bin/bash"
  "ssh_enabled|.options.ssh.enabled|bool|false"
  "impermanence_enabled|.options.impermanence.enabled|bool|false"
  "impermanence_dataset|.options.impermanence.dataset|scalar|rpool/persist"
  "impermanence_mount|.options.impermanence.mount|scalar|/persist"
  "age_key_url|.options.age_key_url|scalar|"
  "hostname|.system.hostname|scalar|"
  "timezone|.system.timezone|scalar|UTC"
  "desktop|.environment.desktop|array|"
  "display_manager|.environment.display_manager|scalar|auto"
  "dotfiles_repo|.dotfiles_repo|scalar|"
  "os_pool_name|.os_pool_name|scalar|rpool"
  "storage_pool_name|.storage_pool_name|scalar|dpool"
  "storage_mount|.storage_mount|scalar|/data"
  "ashift|.ashift|scalar|12"
  "os_pool_ashift|.os_pool.ashift|scalar|13"
  "encryption_enabled|.options.encryption|bool|false"
  "filesystem|.filesystem|scalar|zfs"
  # Manual Partitioning (ADR 0073): the disk-config kind discriminator. Absent
  # ⇒ auto (today's pool skeleton); manual selects the flat partitions[] path.
  "disk_kind|.disk_config.kind|scalar|auto"
)

# install_config_get <name> — schema dispatcher for the generated wrappers.
# Reads the named field according to its schema row and applies the default.
install_config_get() {
  local name="$1" spec n p t d v
  for spec in "${_INSTALL_CONFIG_SCHEMA[@]}"; do
    IFS='|' read -r n p t d <<< "$spec"
    [[ "$n" == "$name" ]] || continue
    v=""
    case "$t" in
    scalar) v="$(cfgo "$p")" ;;
    bool)
      v="$(jsonc_read "$CONFIG_FILE" "$p")"
      [[ "$v" == "null" ]] && v=""
      ;;
    array) v="$(_install_config_array "$p")" ;;
    esac
    if [[ -n "$v" ]]; then
      printf '%s\n' "$v"
    elif [[ -n "$d" ]]; then
      printf '%s\n' "$d"
    fi
    return
  done
  error "install_config_get: unknown name '$name'"
}

# Generate one wrapper per schema row. Each wrapper forwards by name to
# install_config_get. The canonical declaration is the schema row above.
for _spec in "${_INSTALL_CONFIG_SCHEMA[@]}"; do
  IFS='|' read -r _name _ _ _ <<< "$_spec"
  eval "install_config_${_name}() { install_config_get ${_name}; }"
done
unset _spec _name

# Manual Partitioning neutralises the pool-dependent options (ADR 0073). A plain
# hand-partitioned layout has no ZFS dataset to roll back and no pool to
# encrypt, so impermanence and encryption read false under kind=manual whatever
# override the (shown-but-locked) menu row still carries — the back-end must
# never act on a stale value the operator cannot edit. These OVERRIDE the
# generated wrappers above (last definition wins), like install_config_any_zfs.
install_config_impermanence_enabled() {
  [[ "$(install_config_disk_kind)" == "manual" ]] \
    && { printf 'false\n'; return; }
  install_config_get impermanence_enabled
}
install_config_encryption_enabled() {
  [[ "$(install_config_disk_kind)" == "manual" ]] \
    && { printf 'false\n'; return; }
  install_config_get encryption_enabled
}

# =============================================================================
# Hand-written specials — kept verbatim because each breaks the schema mould.
# =============================================================================

# Array reader: accepts string ("kde"), array (["kde"]), or
# null/absent. Emits one line per element; zero lines when absent/null.
_install_config_array() {
  jsonc_read "$CONFIG_FILE" "$1 | if type == \"array\" then .[]
    elif type == \"string\" then . else empty end"
}

install_config_gpu() {
  local out; out="$(_install_config_array '.environment.gpu')"
  printf '%s\n' "${out:-auto}"
}

# Encryption method (ADR 0040) — scalar with a filesystem-derived default. The
# enablement bool (install_config_encryption_enabled) is untouched; this only
# names the cipher seam: ZFS uses native AES, every other filesystem uses LUKS.
# An explicit options.encryption_method wins.
install_config_encryption_method() {
  local v; v="$(cfgo '.options.encryption_method')"
  if [[ -n "$v" ]]; then
    printf '%s\n' "$v"
  elif [[ "$(install_config_filesystem)" == "zfs" ]]; then
    printf '%s\n' "native"
  else
    printf '%s\n' "luks"
  fi
}

# Locale / Keymap Selection (ADR 0036) — scalar|array union. Element 0 is the
# default (LANG / console KEYMAP); the rest are generated locales / available
# desktop layouts. *s accessors emit one token per line (primary first); the
# singular accessors return the primary, the back-compat scalar consumers use.
install_config_locales() {
  local out; out="$(_install_config_array '.system.locale')"
  printf '%s\n' "${out:-en_US.UTF-8}"
}

install_config_locale() { install_config_locales | head -n1; }

install_config_keymaps() {
  local out; out="$(_install_config_array '.system.keymap')"
  printf '%s\n' "${out:-us}"
}

install_config_keymap() { install_config_keymaps | head -n1; }

# Mirror Countries (issue 06) — accepts a single country (string) or a list.
# Emits one country per line, order preserved, feeding `reflector --country`.
# Defaults to the operator's near-DE set when absent or null. Scalar|array
# union like the locale/keymap specials.
install_config_mirror_countries() {
  local out; out="$(_install_config_array '.options.mirror_countries')"
  if [[ -z "$out" ]]; then
    printf '%s\n' Germany Switzerland Sweden France Romania
  else
    printf '%s\n' "$out"
  fi
}

# Optional Repositories (ADR 0072) — the pacman repos enabled beyond core/extra:
# any of `multilib`, `multilib-testing`, `core-testing`, `extra-testing`. Emits
# one repo per line. Defaults to `multilib` when the key is absent, preserving
# the historical `options.multilib=true` default; an explicit empty array (`[]`)
# means "no optional repos" and is honoured (multilib off).
install_config_optional_repos() {
  local raw; raw="$(jsonc_read "$CONFIG_FILE" '.options.optional_repos')"
  if [[ "$raw" == "null" ]]; then
    printf '%s\n' multilib
  else
    _install_config_array '.options.optional_repos'
  fi
}

# install_config_multilib — back-compat shim: "true" iff `multilib` is among the
# Optional Repositories, so the historical bool read-site keeps working.
install_config_multilib() {
  install_config_optional_repos | grep -qx multilib && echo true || echo false
}

# Custom mirror servers (ADR 0072) — operator-supplied `Server = <url>` lines
# prepended to the reflector-built mirrorlist. One URL per line, order preserved,
# empty when unset.
install_config_mirror_servers() {
  _install_config_array '.options.mirror_servers'
}

# Custom repositories (ADR 0072) — archinstall-style extra pacman repos. Emits
# one repo per line as TSV `name<TAB>url<TAB>sign_check<TAB>sign_option`
# (sign_check ∈ Never|Optional|Required, sign_option ∈ TrustAll|TrustedOnly;
# both default to the pacman-standard Required/TrustedOnly when omitted). Empty
# when none are declared.
install_config_custom_repositories() {
  jsonc_read "$CONFIG_FILE" '.options.custom_repositories' 2>/dev/null \
    | jq -r '(. // [])[]
       | [ .name, .url,
           (.sign_check // "Required"), (.sign_option // "TrustedOnly") ]
       | @tsv' 2>/dev/null
}

# Kernel Selection — accepts a single flavour token (string) or a list. Emits
# one token per line, ordered, primary (first selected) first. Defaults to
# 'lts' when absent or null. Aborts on any unknown flavour token, so a typo
# cannot silently install the wrong or no kernel.
install_config_kernels() {
  local out tok
  out="$(_install_config_array '.options.kernel')"
  out="${out:-lts}"
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    kernel_is_valid_token "$tok" || {
      error "Unknown kernel token in options.kernel: '$tok'.
  Valid tokens: $(kernel_valid_tokens). See ADR 0024."
      return 1
    }
  done <<< "$out"
  printf '%s\n' "$out"
}

# Primary Kernel — the first selected token. Back-compat scalar accessor for
# consumers (initramfs preset, bootloader default) that understand one kernel.
install_config_kernel() {
  install_config_kernels | head -n1
}

install_config_storage_group_ashift() {
  local v; v="$(cfgo ".storage_groups[$1].ashift")"
  printf '%s\n' "${v:-12}"
}

# Number of declared storage_groups[] entries (0 when absent).
install_config_storage_groups_count() {
  jsonc_read "$CONFIG_FILE" '(.storage_groups // []) | length'
}

# Storage Group name at index — emitted raw.
install_config_storage_group_name() {
  cfgo ".storage_groups[$1].name"
}

# Per-group filesystem (ADR 0043) — like the data_pool reader; absent inherits
# the root `filesystem`.
install_config_storage_group_filesystem() {
  local v; v="$(cfgo ".storage_groups[$1].filesystem")"
  printf '%s\n' "${v:-$(install_config_filesystem)}"
}

# Per-group encryption (ADR 0043) — independent bool, default false; explicit
# null check so a stored `false` round-trips (jq gotcha).
install_config_storage_group_encryption() {
  local v; v="$(jsonc_read "$CONFIG_FILE" ".storage_groups[$1].encryption")"
  [[ "$v" == "true" ]] && printf 'true\n' || printf 'false\n'
}

# Owners access list (pool-owners, ADR 0031) — one token per line, in order; a
# bare token is a user, an @-prefixed token a group. Empty when absent. Defined
# for both pool kinds; the Owners Resolver decides chown vs ACL from the tokens.
install_config_storage_group_owners() {
  jsonc_read "$CONFIG_FILE" ".storage_groups[$1].owners[]?"
}

install_config_data_pool_owners() {
  jsonc_read "$CONFIG_FILE" ".data_pools[$1].owners[]?"
}

# =============================================================================
# Standalone Data Pools — data_pools[] accessors (ADR 0027)
# =============================================================================
# Each entry becomes its own zpool. name + disks are required (read raw);
# topology, mount, ashift carry defaults. Indexed like the storage-group
# ashift special above.

# Number of declared data_pools[] entries (0 when absent).
install_config_data_pools_count() {
  jsonc_read "$CONFIG_FILE" '(.data_pools // []) | length'
}

# Pool name at index — the literal zpool name. Emitted raw.
install_config_data_pool_name() {
  cfgo ".data_pools[$1].name"
}

# Topology at index — defaults to 'stripe'.
install_config_data_pool_topology() {
  local v; v="$(cfgo ".data_pools[$1].topology")"
  printf '%s\n' "${v:-stripe}"
}

# Mountpoint at index — defaults to /data/<name>.
install_config_data_pool_mount() {
  local v; v="$(cfgo ".data_pools[$1].mount")"
  if [[ -z "$v" ]]; then
    v="/data/$(install_config_data_pool_name "$1")"
  fi
  printf '%s\n' "$v"
}

# Ashift at index — defaults to 12.
install_config_data_pool_ashift() {
  local v; v="$(cfgo ".data_pools[$1].ashift")"
  printf '%s\n' "${v:-12}"
}

# Disks at index — one device path per line.
install_config_data_pool_disks() {
  jsonc_read "$CONFIG_FILE" ".data_pools[$1].disks[]?"
}

# Per-group filesystem (ADR 0043) — a Standalone Data Pool may pick its own
# filesystem; absent inherits the root `filesystem`. An explicit value wins.
install_config_data_pool_filesystem() {
  local v; v="$(cfgo ".data_pools[$1].filesystem")"
  printf '%s\n' "${v:-$(install_config_filesystem)}"
}

# Per-group encryption (ADR 0043) — an independent bool, default false. Read raw
# with an explicit null check so a stored `false` round-trips (a `// false`
# default cannot distinguish absent from an explicit false — jq gotcha).
install_config_data_pool_encryption() {
  local v; v="$(jsonc_read "$CONFIG_FILE" ".data_pools[$1].encryption")"
  [[ "$v" == "true" ]] && printf 'true\n' || printf 'false\n'
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
  local n i
  n="$(install_config_data_pools_count)"
  for ((i = 0; i < n; i++)); do
    [[ "$(install_config_data_pool_filesystem "$i")" == "zfs" ]] \
      && { printf 'true\n'; return; }
  done
  n="$(install_config_storage_groups_count)"
  for ((i = 0; i < n; i++)); do
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
  jsonc_read "$CONFIG_FILE" '(.disk_config.partitions // []) | length'
}

# Whole partitions[] array as compact JSON (the planner input; [] when absent).
install_config_partitions_json() {
  jsonc_read "$CONFIG_FILE" '(.disk_config.partitions // []) | tojson'
}

# Per-partition fields at index — emitted raw.
install_config_partition_device() {
  cfgo ".disk_config.partitions[$1].device"
}
install_config_partition_mountpoint() {
  cfgo ".disk_config.partitions[$1].mountpoint"
}
install_config_partition_fs() {
  cfgo ".disk_config.partitions[$1].fs"
}

# Format flag — true unless explicitly false (a kept/reused partition).
install_config_partition_format() {
  local v; v="$(jsonc_read "$CONFIG_FILE" ".disk_config.partitions[$1].format")"
  [[ "$v" == "false" ]] && { printf 'false\n'; return; }
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
  local n i
  n="$(install_config_data_pools_count)"
  for ((i = 0; i < n; i++)); do
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
  local fs="$1"
  [[ "$(install_config_filesystem)" == "$fs" ]] && { printf 'true\n'; return; }
  local n i
  n="$(install_config_data_pools_count)"
  for ((i = 0; i < n; i++)); do
    [[ "$(install_config_data_pool_filesystem "$i")" == "$fs" ]] \
      && { printf 'true\n'; return; }
  done
  n="$(install_config_storage_groups_count)"
  for ((i = 0; i < n; i++)); do
    [[ "$(install_config_storage_group_filesystem "$i")" == "$fs" ]] \
      && { printf 'true\n'; return; }
  done
  printf 'false\n'
}
