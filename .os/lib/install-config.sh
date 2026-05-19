#!/usr/bin/env bash
# =============================================================================
# lib/install-config.sh — Install Config Reader (typed accessors)
# =============================================================================
# Sole owner of Install Config schema defaults. Each install_config_* accessor
# reads CONFIG_FILE (set by lib/config.sh) and applies the canonical default.
#
# Sourced by 03-install.sh after lib/common.sh (which provides cfgo).
# =============================================================================

# shellcheck source=./common.sh
[[ "$(type -t cfgo)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/common.sh"

install_config_kernel() {
  local v; v="$(cfgo '.options.kernel')"
  printf '%s\n' "${v:-lts}"
}

install_config_bootloader() {
  local v; v="$(cfgo '.options.bootloader')"
  printf '%s\n' "${v:-systemd-boot}"
}

# Bool-safe reader: cfgo uses `// empty`, which collapses jq-false to "" along
# with null. For boolean fields we must distinguish absent from explicit false,
# so we read raw and treat only literal `null` as missing.
_install_config_bool() {
  local path="$1" default="$2" v
  v="$(jsonc_read "$CONFIG_FILE" "$path")"
  [[ "$v" == "null" ]] && v=""
  printf '%s\n' "${v:-$default}"
}

install_config_swap_enabled() {
  _install_config_bool '.options.swap' 'true'
}

install_config_esp_size() {
  local v; v="$(cfgo '.options.esp_size')"
  printf '%s\n' "${v:-512M}"
}

install_config_impermanence_enabled() {
  _install_config_bool '.options.impermanence.enabled' 'false'
}

install_config_impermanence_dataset() {
  local v; v="$(cfgo '.options.impermanence.dataset')"
  printf '%s\n' "${v:-rpool/persist}"
}

install_config_impermanence_mount() {
  local v; v="$(cfgo '.options.impermanence.mount')"
  printf '%s\n' "${v:-/persist}"
}

install_config_age_key_url() {
  cfgo '.options.age_key_url'
}

install_config_hostname() {
  cfgo '.system.hostname'
}

install_config_locale() {
  local v; v="$(cfgo '.system.locale')"
  printf '%s\n' "${v:-en_US.UTF-8}"
}

install_config_timezone() {
  local v; v="$(cfgo '.system.timezone')"
  printf '%s\n' "${v:-UTC}"
}

install_config_keymap() {
  local v; v="$(cfgo '.system.keymap')"
  printf '%s\n' "${v:-us}"
}

# Array reader: accepts string ("kde"), array (["kde","hyprland"]), or
# null/absent. Emits one line per element; zero lines when absent/null.
_install_config_array() {
  jsonc_read "$CONFIG_FILE" "$1 | if type == \"array\" then .[]
    elif type == \"string\" then . else empty end"
}

install_config_desktop() {
  _install_config_array '.environment.desktop'
}

install_config_gpu() {
  local out; out="$(_install_config_array '.environment.gpu')"
  printf '%s\n' "${out:-auto}"
}

install_config_extras_backup() {
  _install_config_bool '.post_install.backup' 'false'
}

install_config_extras_security() {
  _install_config_bool '.post_install.security' 'false'
}

install_config_packages_extra() {
  _install_config_array '.packages.extra'
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

install_config_dotfiles_repo() {
  cfgo '.dotfiles_repo'
}
