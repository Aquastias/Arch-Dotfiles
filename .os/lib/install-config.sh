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
