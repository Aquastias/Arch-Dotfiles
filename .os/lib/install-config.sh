#!/usr/bin/env bash
# =============================================================================
# lib/install-config.sh — Install Config Reader (typed accessors)
# =============================================================================
# Sole owner of Install Config schema defaults. The schema below is the
# canonical declaration of every regular Install Config field: jq path, type
# and default value. The `install_config_<name>` wrappers are generated from
# this schema at source time and forward to `install_config_get`.
#
# To find where `install_config_kernel` (or any other regular accessor) is
# defined, grep this file for the schema row — that is the declaration site.
# Four genuinely-special accessors remain hand-written below the schema.
#
# Sourced by 03-install.sh after lib/common.sh (which provides cfgo).
# =============================================================================

# shellcheck source=./common.sh
[[ "$(type -t cfgo)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/common.sh"

# Schema rows: name|jq_path|type|default
# Type ∈ {scalar, bool, array}. Empty default = emit empty when absent.
_INSTALL_CONFIG_SCHEMA=(
  "kernel|.options.kernel|scalar|lts"
  "bootloader|.options.bootloader|scalar|systemd-boot"
  "swap_enabled|.options.swap|bool|true"
  "esp_size|.options.esp_size|scalar|512M"
  "impermanence_enabled|.options.impermanence.enabled|bool|false"
  "impermanence_dataset|.options.impermanence.dataset|scalar|rpool/persist"
  "impermanence_mount|.options.impermanence.mount|scalar|/persist"
  "age_key_url|.options.age_key_url|scalar|"
  "hostname|.system.hostname|scalar|"
  "locale|.system.locale|scalar|en_US.UTF-8"
  "timezone|.system.timezone|scalar|UTC"
  "keymap|.system.keymap|scalar|us"
  "desktop|.environment.desktop|array|"
  "extras_backup|.post_install.backup|bool|false"
  "extras_security|.post_install.security|bool|false"
  "packages_extra|.packages.extra|array|"
  "dotfiles_repo|.dotfiles_repo|scalar|"
  "os_pool_name|.os_pool_name|scalar|rpool"
  "storage_pool_name|.storage_pool_name|scalar|dpool"
  "storage_mount|.storage_mount|scalar|/data"
  "ashift|.ashift|scalar|12"
  "os_pool_ashift|.os_pool.ashift|scalar|13"
  "encryption_enabled|.options.encryption|bool|false"
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

# =============================================================================
# Hand-written specials — kept verbatim because each breaks the schema mould.
# =============================================================================

# Array reader: accepts string ("kde"), array (["kde","hyprland"]), or
# null/absent. Emits one line per element; zero lines when absent/null.
_install_config_array() {
  jsonc_read "$CONFIG_FILE" "$1 | if type == \"array\" then .[]
    elif type == \"string\" then . else empty end"
}

install_config_gpu() {
  local out; out="$(_install_config_array '.environment.gpu')"
  printf '%s\n' "${out:-auto}"
}

install_config_packages_groups() {
  jsonc_read "$CONFIG_FILE" '
    .packages.groups // {}
    | to_entries[]?
    | select(.key | startswith("_") | not)
    | select(.value | type == "array")
    | .value[]?
  '
}

install_config_storage_group_ashift() {
  local v; v="$(cfgo ".storage_groups[$1].ashift")"
  printf '%s\n' "${v:-12}"
}
