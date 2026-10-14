#!/usr/bin/env bash
# =============================================================================
# lib/config/install-config.sh — Install Config Reader (typed accessors)
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
# Per-group accessors live in install-config-groups.sh (sourced at the end).
#
# Requires lib/common.sh (config_optional) already sourced.
#
# Used by: 01-bootstrap-zfs.sh, 03-install.sh, lib/feature-audit/manifest.sh,
# and every install-time lib reading the Install Config.
# =============================================================================

# shellcheck source=../common.sh
declare -F config_optional >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../common.sh"

# shellcheck source=../packages/kernel.sh
declare -F kernel_is_valid_token >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../packages/kernel.sh"

# Schema rows: name|jq_path|type|default
# Type ∈ {scalar, bool, array}. Empty default = emit empty when absent.
_INSTALL_CONFIG_SCHEMA=(
  "bootloader|.options.bootloader|scalar|systemd-boot"
  "swap_enabled|.options.swap|bool|true"
  "zswap_enabled|.options.zswap.enabled|bool|true"
  "zswap_compressor|.options.zswap.compressor|scalar|zstd"
  "zswap_max_pool_percent|.options.zswap.max_pool_percent|scalar|20"
  "esp_size|.options.esp_size|scalar|auto"
  "root_shell|.options.root_shell|scalar|/bin/bash"
  "ssh_enabled|.options.ssh.enabled|bool|false"
  # Printing Service (ADR 0079): the toggle-derived print-daemon switch, default
  # on. cups is injected into host_programs from this at assembly; this is the
  # typed back-end reader (printing_enabled in printing.sh reads the raw config
  # for the pure injector/resolver).
  "printing_enabled|.options.printing.enabled|bool|true"
  # Bluetooth Service (ADR 0080): the toggle-derived bluez switch, default on.
  # The `bluetooth` program is injected into host_programs from this at
  # assembly; bluetooth_enabled in bluetooth.sh reads the raw config for the
  # pure injector/resolver.
  "bluetooth_enabled|.options.bluetooth.enabled|bool|true"
  # Power Profile (ADR 0080): the enum-derived power-management backend, default
  # power-profiles-daemon. The value maps to a Host Program (ppd/tuned)
  # injected into host_programs at assembly; none installs nothing.
  "power_profile|.options.power.profile|scalar|power-profiles-daemon"
  "impermanence_enabled|.options.impermanence.enabled|bool|false"
  "impermanence_dataset|.options.impermanence.dataset|scalar|rpool/persist"
  "impermanence_mount|.options.impermanence.mount|scalar|/persist"
  "age_key_url|.options.age_key_url|scalar|"
  "hostname|.system.hostname|scalar|"
  # timezone is NOT a schema row: it is resolved, not read raw (ADR 0118), so it
  # is a hand-written special below (it breaks the pure-default mould, like the
  # array/kernel specials).
  # Primary User display name → GECOS via useradd -c (ADR 0121). Default "Alex"
  # (the operator's), applied to the Primary User only by the Runner; an
  # explicit value overrides. Not a per-user schema — that is out of scope.
  "fullname|.system.fullname|scalar|Alex"
  # Console font (ADR 0076) — the Locales console-font leaf, written as FONT= in
  # /etc/vconsole.conf. default8x16 is always present (kbd ∈ base).
  "console_font|.system.console_font|scalar|default8x16"
  "desktop|.environment.desktop|array|"
  "display_manager|.environment.display_manager|scalar|auto"
  "wayland_shell|.environment.wayland_shell|scalar|noctalia"
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
  # Pacman Options (ADR 0074): the pacman [options] block flags the Pacman
  # Configuration Category surfaces. Applied authoritatively to the host
  # /etc/pacman.conf before pacstrap; CheckSpace is deliberately absent (the ZFS
  # path force-disables it) and multilib stays under Optional Repositories.
  "pacman_ilovecandy|.options.pacman.ilovecandy|bool|true"
  "pacman_color|.options.pacman.color|bool|true"
  "pacman_verbose_pkg_lists|.options.pacman.verbose_pkg_lists|bool|true"
  "pacman_disable_download_timeout|.options.pacman.disable_download_timeout|bool|false"
  "pacman_no_progress_bar|.options.pacman.no_progress_bar|bool|false"
  "pacman_parallel_downloads|.options.pacman.parallel_downloads|scalar|5"
)

# install_config_get <name> — schema dispatcher for the generated wrappers.
# Reads the named field according to its schema row and applies the default.
install_config_get() {
  local name="$1" schema_row field_name jq_path field_type default_value value
  for schema_row in "${_INSTALL_CONFIG_SCHEMA[@]}"; do
    IFS='|' read -r field_name jq_path field_type default_value \
      <<< "$schema_row"
    [[ "$field_name" == "$name" ]] || continue
    value=""
    case "$field_type" in
    scalar) value="$(config_optional "$jq_path")" ;;
    bool)
      value="$(jsonc_read "$CONFIG_FILE" "$jq_path")"
      [[ "$value" == "null" ]] && value=""
      ;;
    array) value="$(_install_config_array "$jq_path")" ;;
    esac
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
    elif [[ -n "$default_value" ]]; then
      printf '%s\n' "$default_value"
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

# AppArmor is selected iff the resolved Security & Backup Extras (ADR 0041)
# hold it — the same rule that installs the program — so the LSM cmdline
# (lib/boot/lsm.sh) and the package always agree. Absent / legacy = off.
install_config_apparmor_enabled() {
  declare -F post_install_programs >/dev/null 2>&1 \
    || source "${BASH_SOURCE[0]%/*}/post-install.sh"
  if post_install_programs \
       "$(jsonc_strip "$CONFIG_FILE" | jq -c '.post_install // {}')" \
     | grep -qx apparmor; then
    printf 'true\n'
  else printf 'false\n'; fi
}

# Timezone is resolved, not read raw (ADR 0118): an explicit/guided value wins,
# else geo-IP autodetect, else Europe/Bucharest. A hand-written special (no
# schema row) because it breaks the pure-default mould. The Timezone resolver is
# sourced by 03-install before the single persist call site; tests that stub
# install_config_timezone override this (last definition wins).
install_config_timezone() {
  timezone_resolve "$(config_optional .)"
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
  local value; value="$(config_optional '.options.encryption_method')"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
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

install_config_locale() {
  install_config_locales | awk 'NR == 1 { print; exit }'
}

install_config_keymaps() {
  local out; out="$(_install_config_array '.system.keymap')"
  printf '%s\n' "${out:-us}"
}

install_config_keymap() {
  install_config_keymaps | awk 'NR == 1 { print; exit }'
}

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
# prepended to the reflector-built mirrorlist. One URL per line, order
# preserved, empty when unset.
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
  local out token
  out="$(_install_config_array '.options.kernel')"
  out="${out:-lts}"
  while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    kernel_is_valid_token "$token" || {
      error "Unknown kernel token in options.kernel: '$token'.
  Valid tokens: $(kernel_valid_tokens). See ADR 0024."
      return 1
    }
  done <<< "$out"
  printf '%s\n' "$out"
}

# Primary Kernel — the first selected token. Back-compat scalar accessor for
# consumers (initramfs preset, bootloader default) that understand one kernel.
install_config_kernel() {
  install_config_kernels | awk 'NR == 1 { print; exit }'
}

# shellcheck source=./install-config-groups.sh
source "${BASH_SOURCE[0]%/*}/install-config-groups.sh"
