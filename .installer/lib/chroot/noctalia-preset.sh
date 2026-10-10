#!/usr/bin/env bash
# =============================================================================
# lib/chroot/noctalia-preset.sh — the shared Noctalia work-shell preset
# =============================================================================
# The Noctalia preset is compositor-agnostic (ADR 0097): niri and Hyprland both
# layer the SAME shell — bar, launcher, notifications, lock, wallpaper, OSD,
# palette, curated plugins — so the preset logic lives here, sourced by both
# `extras/desktop/niri/niri.sh` and `extras/desktop/hyprland/hyprland.sh`. Only
# the compositor config file (config.kdl vs hyprland.lua) and the plugin SLICE
# (niri-* vs hypr-*) differ; the seeded `config.toml` is byte-identical.
#
# Extracted from the niri adapter (ADR 0090/0093/0095) with no behaviour change.
# The DECISION to run it (wayland_shell=noctalia) stays with each adapter; this
# module only does the work once it is called.
#
# Caller contract — set these before calling noctalia_preset_install:
#   NOCTALIA_JSON          install-noctalia.jsonc (component + slice bools)
#   NOCTALIA_SEED_ROOT     prefix for /etc/skel seeds (default: / — the chroot)
#   NOCTALIA_CURATED_DIR   staged curated dotfiles source (.config/.local tree)
#   NOCTALIA_BATTERY_GLOB      battery-presence glob for laptop detection
#   NOCTALIA_SLICE_FUNCTION      compositor plugin-slice function
#                                (noctalia_niri_plugins | …)
# Optional overrides (defaults below): NOCTALIA_COMMUNITY_REPO,
# NOCTALIA_COMMUNITY_REF,
#   NOCTALIA_PLUGIN_DATA.
# =============================================================================

[[ -n "${_NOCTALIA_PRESET_SH_SOURCED:-}" ]] && return 0
_NOCTALIA_PRESET_SH_SOURCED=1
# parent_directory / base_name — the chroot-world path helpers (sibling).
# shellcheck source=./chroot-common.sh
declare -F parent_directory >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/chroot-common.sh"
# Seeding the curated config into /etc/skel.
# shellcheck source=./noctalia-skeleton.sh
source "${BASH_SOURCE[0]%/*}/noctalia-skeleton.sh"

# The pure Noctalia package maps (preset base, core+slice plugins, deps),
# shared with the Package Resolver so install and query cannot drift (ADR 0090).
# shellcheck source=/dev/null
declare -F noctalia_preset_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../packages/noctalia.sh"

# Community plugin source, pinned to one v5 commit (ADR 0093) — a single ref
# covers the whole enriched set for every compositor (bump = one SHA).
_NOC_REPO_DEFAULT="https://github.com/noctalia-dev/community-plugins.git"
_NOC_REF_DEFAULT="caed21ab081948435cd770d2e954c99b8bbb72cf"
NOCTALIA_COMMUNITY_REPO="${NOCTALIA_COMMUNITY_REPO:-$_NOC_REPO_DEFAULT}"
NOCTALIA_COMMUNITY_REF="${NOCTALIA_COMMUNITY_REF:-$_NOC_REF_DEFAULT}"
# Where a plugin folder is vendored so a fresh box discovers it as `[local]`
# (ADR 0093/0094): the skel DATA dir. The stowed one-shot enables what it finds.
: "${NOCTALIA_PLUGIN_DATA:=etc/skel/.local/share/noctalia/plugins}"

# _noctalia_preset_flag <key> — an install-noctalia.jsonc component bool (false
# if absent).
_noctalia_preset_flag() {
  [[ -f "$NOCTALIA_JSON" ]] || { echo false; return; }
  jsonc "$NOCTALIA_JSON" | jq -r --arg k "$1" '.[$k] // false'
}

# _noctalia_preset_is_laptop — laptop? install-noctalia.jsonc `laptop` wins when
# set to a boolean (true/false); "auto" (the default) or absence falls back to
# detecting a battery. Gates the battery plugin pair (ADR 0093).
_noctalia_preset_is_laptop() {
  local value="auto"
  [[ -f "$NOCTALIA_JSON" ]] && value="$(jsonc "$NOCTALIA_JSON" \
    | jq -r 'if has("laptop") then (.laptop|tostring) else "auto" end')"
  case "$value" in
    true)  echo true;  return ;;
    false) echo false; return ;;
  esac
  local battery_glob="${NOCTALIA_BATTERY_GLOB:-/sys/class/power_supply/BAT*}"
  compgen -G "$battery_glob" >/dev/null 2>&1 \
    && echo true || echo false
}

# _noctalia_preset_seed_plugin <repo> <ref> <subdir> — sparse-checkout <subdir>
# at <ref> into the skel data dir. Returns non-zero on any git/parse failure so
# a caller can warn-and-continue (invoked in an `if`, so set -e is suppressed
# inside — a network failure never aborts the install). plugin.toml presence + a
# non-empty id are validated so a half-checkout is treated as a failure.
_noctalia_preset_seed_plugin() {
  local repo="$1" git_revision="$2" sub="$3" temporary_directory
  temporary_directory="$(mktemp -d)" || return 1
  local checkout="$temporary_directory/op"
  local destination="${NOCTALIA_SEED_ROOT%/}/${NOCTALIA_PLUGIN_DATA}/${sub}"
  if ! _noctalia_preset_checkout_plugin "$repo" "$git_revision" "$sub" \
         "$checkout"; then
    rm -rf "$temporary_directory"
    return 1
  fi
  mkdir -p "$(parent_directory "$destination")"
  rm -rf "$destination"
  cp -r "$checkout/$sub" "$destination"
  rm -rf "$temporary_directory"
}

# _noctalia_preset_checkout_plugin <repo> <ref> <subdir> <checkout> — a
# sparse checkout of <subdir> at <ref>, valid only with a plugin.toml that
# names a non-empty id.
_noctalia_preset_checkout_plugin() {
  local repo="$1" git_revision="$2" sub="$3" checkout="$4"
  git clone --filter=blob:none --no-checkout --sparse "$repo" "$checkout" \
    && git -C "$checkout" sparse-checkout set "$sub" \
    && git -C "$checkout" checkout "$git_revision" \
    && [[ -f "$checkout/$sub/plugin.toml" ]] \
    && [[ -n "$(_noctalia_preset_plugin_id "$checkout/$sub/plugin.toml")" ]]
}

# _noctalia_preset_plugin_id <plugin.toml> — the first `id = "…"` line's value.
_noctalia_preset_plugin_id() {
  awk 'match($0, /^[[:space:]]*id[[:space:]]*=[[:space:]]*"[^"]+"/) {
      value = substr($0, RSTART, RLENGTH)
      sub(/^[^"]*"/, "", value); sub(/"$/, "", value)
      print value; exit }' "$1"
}

# _noctalia_preset_vendor_plugin <repo> <ref> <sub> —
# _noctalia_preset_seed_plugin with a shallow retry (3 tries, 5s/15s apart): a
# network blip must not drop the plugin.
_noctalia_preset_vendor_plugin() {
  local try
  for try in 1 2 3; do
    _noctalia_preset_seed_plugin "$@" && return 0
    ((try < 3)) && sleep $((try == 1 ? 5 : 15))
  done
  return 1
}

# _noctalia_preset_collect_plugins <plugin-list-fn> — append each plugin the
# list-fn names that is enabled (per its install-noctalia.jsonc bool) plus its
# tool deps to the enabled_plugins / plugin_dependencies accumulators (ADR
# 0093).
_noctalia_preset_collect_plugins() {
  local plugin
  while IFS= read -r plugin; do
    [[ "$(_noctalia_preset_flag "$plugin")" == true ]] || continue
    enabled_plugins+=("$plugin")
    mapfile -t -O "${#plugin_dependencies[@]}" plugin_dependencies \
      < <(noctalia_plugin_deps "$plugin")
  done < <("$1")
}

# noctalia_preset_install <cfg-src-rel> <cfg-dst-rel> — install + seed the whole
# preset. <cfg-src-rel>/<cfg-dst-rel> are the compositor config file relative to
# the curated dir / skel (config.kdl on niri, hyprland.lua on Hyprland); the
# shared config.toml + noctalia-* helpers are always seeded. Uses the section/
# info/warn helpers the sourcing adapter already has from extras-common.sh.
noctalia_preset_install() {
  local config_source="$1" config_destination="$2"
  _noctalia_preset_install_packages
  noctalia_skeleton_seed "$config_source" "$config_destination"
  _noctalia_preset_install_plugins
}

# Base preset (pure map) + the enabled optional companions (cava, cliphist).
_noctalia_preset_install_packages() {
  section "Noctalia work shell"
  local packages=()
  mapfile -t packages < <(noctalia_preset_packages)
  [[ "$(_noctalia_preset_flag cava)" == true ]]     && packages+=(cava)
  [[ "$(_noctalia_preset_flag cliphist)" == true ]] && packages+=(cliphist)
  pacman -S --noconfirm --needed "${packages[@]}"
}

# Enriched plugin set (ADR 0093/0097): the shared core plus this compositor's
# slice, each gated by its install-noctalia.jsonc bool (default on). Collect
# both + their official-repo tool deps, install deps in one pass, then vendor
# each at the pinned ref (the first-login one-shot enables them). A fetch
# failure warns and continues, so one bad plugin never aborts the install.
_noctalia_preset_install_plugins() {
  section "Noctalia plugin set"
  # Filled by _noctalia_preset_collect_plugins.
  local enabled_plugins=() plugin_dependencies=()
  _noctalia_preset_collect_plugins noctalia_core_plugins
  [[ -n "${NOCTALIA_SLICE_FUNCTION:-}" ]] \
    && _noctalia_preset_collect_plugins "$NOCTALIA_SLICE_FUNCTION"

  # Battery plugins (ADR 0093) — laptop-gated: added only on a machine with a
  # battery, or when install-noctalia.jsonc forces `laptop`. Desktops get none.
  if [[ "$(_noctalia_preset_is_laptop)" == true ]]; then
    _noctalia_preset_collect_plugins noctalia_laptop_plugins
  fi

  [[ ${#plugin_dependencies[@]} -gt 0 ]] \
    && pacman -S --noconfirm --needed "${plugin_dependencies[@]}"
  local plugin
  for plugin in "${enabled_plugins[@]:-}"; do
    [[ -n "$plugin" ]] || continue
    if _noctalia_preset_vendor_plugin "$NOCTALIA_COMMUNITY_REPO" \
         "$NOCTALIA_COMMUNITY_REF" "$plugin"
    then info "Plugin $plugin vendored."
    else warn "Plugin $plugin fetch failed (offline?) — skipped."; fi
  done
}
