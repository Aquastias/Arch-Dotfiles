#!/usr/bin/env bash
# =============================================================================
# lib/packages/package-resolver-desktop.sh — Package Resolver desktop sets
# =============================================================================
# The Desktop Environment Adapters' own derived sets for the Package Resolver:
# KDE from its install-kde.jsonc (ADR 0021); niri and Hyprland share the pure
# Noctalia preset keyed on environment.wayland_shell (ADR 0090/0097), as does
# Umbriel, plus its repo core + AUR compositor (ADR 0159). Read from the same
# lists + bools the adapters install from, so query and install cannot drift.
# Also the display-manager set, derived from the desktop set and the effective
# shell (ADR 0069/0158).
#
# Used by: lib/packages/package-resolver.sh (sources it; uses its
# _package_resolver_emit / _package_resolver_jq).
# =============================================================================

# _package_resolver_desktop_packages <desktop> <config> — one Desktop
# Environment Adapter's own sets.
_package_resolver_desktop_packages() {
  local desktop="$1" config="${2:-}"
  if [[ "$desktop" == niri ]]; then
    _package_resolver_niri_packages "$config"
    return 0
  fi
  # Hyprland shares the same Noctalia preset (ADR 0097), keyed on
  # wayland_shell, with the Hyprland plugin slice. Its compositor core is
  # installed by the adapter directly (not resolver-tracked), as it always has
  # been.
  if [[ "$desktop" == hyprland ]]; then
    _package_resolver_noctalia_preset "$config" noctalia_hyprland_plugins
    return 0
  fi
  if [[ "$desktop" == umbriel ]]; then
    _package_resolver_umbriel_packages "$config"
    return 0
  fi
  local adapter_file
  adapter_file="${INSTALLER_DIR:-}/extras/desktop/${desktop}"
  adapter_file+="/install-${desktop}.jsonc"
  [[ -f "$adapter_file" ]] || return 0
  local json; json="$(jsonc_strip "$adapter_file" 2>/dev/null)" || return 0
  _package_resolver_adapter_sets "$desktop" "$json" "$config"
}

# _package_resolver_adapter_sets <desktop> <adapter-json> <config> — the sets
# a jsonc-driven adapter (KDE) declares: shell, apps, plugins, AUR.
_package_resolver_adapter_sets() {
  local desktop="$1" json="$2" config="$3"

  # The shell section is now DATA — the shell_packages Categorized List in the
  # adapter's install-<desktop>.jsonc, read here so the report matches exactly
  # what the adapter installs (source of truth, not a mirror). Honor .shell ==
  # false (jq's // treats false as empty, so an explicit check, not `.shell //
  # true`). sddm the PACKAGE moved to the display-manager set (ADR 0069);
  # sddm-kcm (a KDE config app) stays with the KDE shell.
  local shell_enabled
  shell_enabled="$(jq -r 'if .shell == false then false else true end' \
    <<<"$json")"
  if [[ "$shell_enabled" == "true" && "$desktop" == "kde" ]]; then
    _package_resolver_emit_list kde-shell "$json" shell_packages
  fi

  # Stock (pure) KDE (ADR 0112): the plasma-meta shell only — no curated shell
  # extras, apps or aur, so the report matches what the stock adapter installs
  # (no query/install drift).
  if [[ "$(install_config_from_json "$config" stock)" \
        == "true" ]]; then
    return 0
  fi
  if [[ "$shell_enabled" == "true" ]]; then
    _package_resolver_emit_list kde-shell "$json" curated_shell_packages
  fi

  if [[ "$(jq -r '.apps // true' <<<"$json")" == "true" ]]; then
    # apps_list (kde-applications group members), apps_extra (non-group KDE
    # apps — ADR 0087) and plugins (per-app optdepend enhancers — ADR 0088):
    # one source each. Adding a fourth section is one line here.
    _package_resolver_emit_list kde-apps "$json" apps_list
    _package_resolver_emit_list kde-apps-extra "$json" apps_extra
    _package_resolver_emit_list kde-plugins "$json" plugins
  fi
  _package_resolver_emit_list kde-aur "$json" aur
}

# _package_resolver_emit_list <source> <adapter-json> <field> — emit the
# enabled entries of the bool Categorized List at .<field>.
_package_resolver_emit_list() {
  local source_name="$1" json="$2" field="$3" package
  while IFS= read -r package; do
    [[ -n "$package" ]] && _package_resolver_emit "$source_name" derived \
      "$package"
  done < <(categorized_list_parse \
    "$(jq -c ".${field} // {}" <<<"$json")" bool "$field" 2>/dev/null)
  return 0
}

# _package_resolver_noctalia_flag <key> <noctalia-json> —
# install-noctalia.jsonc bool (false if absent).
_package_resolver_noctalia_flag() {
  jq -r --arg k "$1" '.[$k] // false' <<<"$2"
}

# _package_resolver_noctalia_plugin_deps <noctalia-json> <list-function> —
# emit the official-repo tool deps of every plugin <list-function> names that
# is enabled in <noctalia-json> (ADR 0093).
_package_resolver_noctalia_plugin_deps() {
  local noctalia_json="$1" list_function="$2" plugin
  while IFS= read -r plugin; do
    [[ "$(_package_resolver_noctalia_flag "$plugin" "$noctalia_json")" \
        == true ]] \
      || continue
    _package_resolver_emit_from noctalia noctalia_plugin_deps "$plugin"
  done < <("$list_function")
}

# _package_resolver_wayland_shell <config> — the effective wayland_shell, as
# the installer resolves it: a stock (pure) compositor (ADR 0112) forces `none`
# regardless of the authored value. Shared by the Noctalia preset and the
# display-manager `auto` rule (ADR 0158).
_package_resolver_wayland_shell() {
  local config="$1"
  if [[ "$(install_config_from_json "$config" stock)" == "true" ]]; then
    printf 'none\n'
  else
    install_config_from_json "$config" wayland_shell
  fi
}

# _package_resolver_noctalia_preset <config> <slice-function> — the SHARED
# Noctalia work preset (source `noctalia`, ADR 0097), keyed on
# environment.wayland_shell: the base preset map, the enabled
# install-noctalia.jsonc companions (cava, cliphist), shared-core plugin deps
# + this compositor's <slice-function> deps, and the laptop-gated battery
# deps. Reused by both the niri and Hyprland resolver paths.
_package_resolver_noctalia_preset() {
  local config="$1" slice_function="$2"
  [[ "$(_package_resolver_wayland_shell "$config")" == noctalia ]] || return 0

  _package_resolver_emit_from noctalia noctalia_preset_packages

  # Optional companions from install-noctalia.jsonc (the shared preset owner
  # file, ADR 0097). The key is the package name for cava/cliphist.
  local noctalia_json=""
  local noctalia_file="${INSTALLER_DIR:-}/extras/desktop/install-noctalia.jsonc"
  if [[ -n "${INSTALLER_DIR:-}" && -f "$noctalia_file" ]]; then
    noctalia_json="$(jsonc_strip "$noctalia_file" 2>/dev/null)"
  fi
  [[ -n "$noctalia_json" ]] || return 0
  [[ "$(jq -r '.cava // false' <<<"$noctalia_json")" == true ]] \
    && _package_resolver_emit noctalia derived cava
  [[ "$(jq -r '.cliphist // false' <<<"$noctalia_json")" == true ]] \
    && _package_resolver_emit noctalia derived cliphist

  # Enriched plugin deps (ADR 0093/0097) — the shared core plus this
  # compositor's slice.
  _package_resolver_noctalia_plugin_deps "$noctalia_json" noctalia_core_plugins
  _package_resolver_noctalia_plugin_deps "$noctalia_json" "$slice_function"

  # Battery plugins are laptop-gated (ADR 0093). The resolver has no target
  # hardware, so it reports the pair only when install-noctalia.jsonc sets
  # `laptop` true; the "auto" default is an install-time /sys decision the
  # adapter makes.
  [[ "$(jq -r 'if has("laptop") then (.laptop|tostring) else "false" end' \
     <<<"$noctalia_json")" == true ]] || return 0
  _package_resolver_noctalia_plugin_deps "$noctalia_json" \
    noctalia_laptop_plugins
}

# _package_resolver_niri_packages <config> — niri's derived sets (ADR 0090).
# The core is the pure niri_core_packages map (shared with the adapter); the
# Noctalia preset is the shared helper with the niri plugin slice.
_package_resolver_niri_packages() {
  _package_resolver_emit_from niri-shell niri_core_packages
  _package_resolver_noctalia_preset "$1" noctalia_niri_plugins
}

# _package_resolver_umbriel_packages <config> — Umbriel's derived sets (ADR
# 0159): the pure repo core map (shared with the adapter), the shared Noctalia
# preset with the (empty) Umbriel slice, and the adapter's `aur` list, which
# carries the compositor itself.
_package_resolver_umbriel_packages() {
  _package_resolver_emit_from umbriel-shell umbriel_core_packages
  _package_resolver_noctalia_preset "$1" noctalia_umbriel_plugins
  local adapter_file="${INSTALLER_DIR:-}/extras/desktop/umbriel"
  adapter_file+="/install-umbriel.jsonc"
  [[ -f "$adapter_file" ]] || return 0
  _package_resolver_emit_list umbriel-aur \
    "$(jsonc_strip "$adapter_file" 2>/dev/null)" aur
}

# _package_resolver_display_manager <config> <desktops> — the greeter, its
# own derived set keyed on the resolved display_manager (ADR 0069), not
# smuggled inside kde-shell. `auto` resolves the same DESKTOP-AWARE way the
# installer does (_environment_resolve_display_manager, ADR 0091/0158): sddm
# when kde is present; else noctalia-greeter under the Noctalia shell, greetd
# otherwise; none when no desktop. Explicit greetd/noctalia-greeter/sddm win.
_package_resolver_display_manager() {
  local config="$1" desktops="$2" display_manager
  display_manager="$(install_config_from_json "$config" display_manager)"
  if [[ -z "$desktops" ]]; then
    display_manager="none"
  elif [[ "$display_manager" == "auto" ]]; then
    if grep -qx kde <<<"$desktops"; then
      display_manager="sddm"
    elif [[ "$(_package_resolver_wayland_shell "$config")" == noctalia ]]; then
      display_manager="noctalia-greeter"
    else
      display_manager="greetd"
    fi
  fi
  case "$display_manager" in
    greetd) _package_resolver_emit display-manager derived \
              greetd greetd-tuigreet ;;
    noctalia-greeter) _package_resolver_emit display-manager derived \
                        greetd noctalia-greeter ;;
    sddm)   _package_resolver_emit display-manager derived sddm ;;
  esac
}
