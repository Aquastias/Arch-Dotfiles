#!/usr/bin/env bash
# =============================================================================
# lib/config/config-state.sh — Guided Installer Config State + seeder
# =============================================================================
# A single in-session Config State: a *sparse override map* over the computed
# defaults (Host Core + accessors). The Guided Installer mutates it through the
# pure verbs below and emits only what the operator changed; the back-end fills
# the rest. The seeder fills a launch state with this operator's computed
# defaults so an untouched guided run is ready to install — independent of menu
# rendering, it writes only Config State (ADR 0039). Pure: in-memory JSON on
# stdin/args → JSON on stdout, no TTY.
#
# Public API:
#   config_state_new                       → fresh (empty) state on stdout
#   config_state_set   <state> <path> <v>  → state with override at <path> = <v>
#   config_state_get   <state> <path>      → raw value at <path> (empty if
#                                            unset)
#   config_state_unset <state> <path>      → state with the override at <path>
#                                            gone
#   config_state_is_overridden <state> <p> → rc 0 if <p> is overridden, else 1
#   config_state_emit  <state>             → the sparse override map (delta)
#   config_state_seed_defaults <state>     → <state> with the launch defaults
#                                            set, resolved over Host Core
#   config_state_host_core                 → Host Core as JSON
#   config_state_install_defaults <state>  → <state> with the schema Install
#                                            Defaults the menu shows laid over
#
# <path> is a dotted JSON path ("system.hostname"); <v> is a JSON value
# ('"eterniox"', 'true', '"single"').
#
# Used by: the Guided Installer (lib/guided/*), lib/config/{edits,emit,menu,
# manual-partition}.sh, lib/matrix/assemble.sh.
# =============================================================================

# shellcheck source=./post-install.sh
declare -F post_install_default >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/post-install.sh"

# shellcheck source=./layer-resolver.sh
declare -F layer_resolver_resolve >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/layer-resolver.sh"

# shellcheck source=./program-registry.sh
declare -F _program_registry_parse >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/program-registry.sh"

# shellcheck source=./install-config.sh
declare -F install_config_default_object >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/install-config.sh"

# shellcheck source=./fonts.sh
declare -F fonts_default_selection_json >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/fonts.sh"

# config_state_new — the initial state: an empty override map.
config_state_new() { printf '%s\n' '{}'; }

# config_state_set <state> <path> <json-value> — record an override at <path>.
config_state_set() {
  local state="$1" path="$2" value="$3"
  jq --arg p "$path" --argjson v "$value" \
    'setpath($p | split("."); $v)' <<<"$state"
}

# config_state_get <state> <path> — the raw value at <path>, empty when unset.
# Only a missing key (null) is empty: a stored `false` is a real value and must
# round-trip ("false"), so this is an explicit null check, not `// empty` (jq's
# // treats false as empty and would swallow a false bool).
config_state_get() {
  local state="$1" path="$2"
  jq -r --arg p "$path" \
    'getpath($p | split(".")) | if . == null then empty else . end' <<<"$state"
}

# config_state_unset <state> <path> — drop the override at <path>. Ancestor
# objects emptied by the deletion are pruned, so a reset field leaves no trace
# in the sparse map (the section disappears when its last override is gone).
config_state_unset() {
  local state="$1" path="$2"
  jq --arg p "$path" '
    delpaths([$p | split(".")])
    | walk(if type == "object" then with_entries(select(.value != {})) else . end)
  ' <<<"$state"
}

# config_state_is_overridden <state> <path> — rc 0 when <path> carries an
# override, rc 1 otherwise. Drives the menu's ● flag.
config_state_is_overridden() {
  local state="$1" path="$2"
  jq -e --arg p "$path" 'getpath($p | split(".")) != null' <<<"$state" >/dev/null
}

# config_state_emit <state> — the sparse override map (a profile delta).
config_state_emit() { jq '.' <<<"$1"; }

# config_state_host_core — Host Core as JSON ({} when absent/unreadable).
# The menu's baseline is LOADED from Host Core rather than hand-copying a few
# of its values (ADR 0058). Hand-copying is why `cups` used to install on every
# host and appear nowhere in the menu (cups is now toggle-derived — ADR 0079),
# and why packages.repo/aur had no menu representation at all.
config_state_host_core() {
  local profile_file="${INSTALLER_DIR:-}/hosts/core/profile.jsonc"
  [[ -n "${INSTALLER_DIR:-}" && -f "$profile_file" ]] \
    || { printf '{}\n'; return 0; }
  _program_registry_parse "$profile_file" 2>/dev/null || printf '{}\n'
}

# config_state_seed_defaults <state> — overlay the launch defaults onto <state>,
# resolved OVER Host Core so everything core installs is visible in the menu.
#
# Host Core is the lower layer and the computed defaults the upper one, folded
# through the Layer Resolver: core's additive contributions (host_programs,
# packages, sysctl, users) survive into the baseline, while the ordered
# selections below (kernel, locale, desktop, mirrors) replace whatever core
# declared. Because these land in the BASELINE and not the override map, they
# render with no ● until the operator actually edits them.
config_state_seed_defaults() {
  local state="$1"
  state="$(_config_state_computed_defaults "$state")"
  layer_resolver_resolve host "$(config_state_host_core)" "$state"
}

# _config_state_computed_defaults <state> — the guided launch defaults alone,
# without Host Core. Split out so the fold above has a clean upper layer.
_config_state_computed_defaults() {
  local state="$1"
  state="$(config_state_install_defaults "$state")"
  _config_state_preset_defaults "$state"
}

# Guided Launch Presets — not Install Defaults: an absent field installs
# something else, or must fail (ADR 0154; absent extras = off, ADR 0041).
_config_state_preset_defaults() {
  local state="$1"
  state="$(config_state_set "$state" system.hostname '"eterniox"')"
  state="$(config_state_set "$state" users '["aquastias"]')"
  state="$(config_state_set "$state" mode '"single"')"
  state="$(config_state_set "$state" system.timezone '"Europe/Bucharest"')"
  state="$(config_state_set "$state" environment.desktop '["kde"]')"
  # Font Catalog (ADR 0080): absent options.fonts resolves to the same set via
  # fonts_selected; seeded so a fresh run shows the default set with no ●.
  state="$(config_state_set "$state" options.fonts \
    "$(fonts_default_selection_json)")"
  state="$(config_state_set "$state" post_install "$(post_install_default)")"
  printf '%s\n' "$state"
}

# Install Defaults the menu shows, from the schema (ADR 0154): the baseline is
# the normalise reference, so re-picking a shown default clears its ●.
_CONFIG_STATE_SCHEMA_SEEDED=(
  console_font kernels display_manager wayland_shell stock mirror_countries
  filesystem disk_kind esp_size bootloader optional_repos encryption_enabled
  impermanence_enabled ssh_enabled printing_enabled bluetooth_enabled
  power_profile pacman_ilovecandy pacman_color pacman_verbose_pkg_lists
  pacman_disable_download_timeout pacman_no_progress_bar
  pacman_parallel_downloads zswap_enabled zswap_compressor
  zswap_max_pool_percent
)

# config_state_install_defaults <state> — the schema defaults laid over
# <state>; locale / keymap / gpu seed their primary as a scalar (menu shape).
config_state_install_defaults() {
  local state="$1" path name
  state="$(jq -c --argjson d "$(install_config_default_object \
    "${_CONFIG_STATE_SCHEMA_SEEDED[@]}")" '. * $d' <<<"$state")"
  while read -r path name; do
    state="$(config_state_set "$state" "$path" \
      "$(install_config_default "$name" | jq -Rn 'input')")"
  done <<'UNIONS'
system.locale locales
system.keymap keymaps
environment.gpu gpu
UNIONS
  printf '%s\n' "$state"
}
