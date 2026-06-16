#!/usr/bin/env bash
# =============================================================================
# lib/config/menu.sh — Guided Installer Menu model (ADR 0039)
# =============================================================================
# Turns a Config State into the menu rows the fzf shell renders. Each row
# carries its section (the Host / Users split), the field's dotted path, a
# label, the current value (override if set, else the default), and the `●`
# override flag. The rows ARE the contract — they drive both the shell and the
# tests, so "full parity" means "every covered field surfaces a row".
#
# Pure: JSON-in/JSON-out, no TTY.
#
# Public API:
#   menu_rows <state>  → JSON array of rows [{section,field,label,value,
#                        overridden}]
# =============================================================================

# shellcheck source=./state.sh
[[ "$(type -t cfgstate_get)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/state.sh"

# Field table — "section|path|label|default". The single source of truth for
# the covered fields; add a row here to surface a field in the menu.
_MENU_FIELDS=(
  "Host|system.hostname|hostname|"
  "Disks|filesystem|filesystem|zfs"
  "Disks|options.encryption|encryption|false"
  "Disks|options.impermanence.enabled|impermanence|false"
  "Users|users|users|"
)

# menu_rows <state> — the menu rows for <state> on stdout (JSON array).
menu_rows() {
  local state="$1" spec section path label default value overridden
  local rows=()
  # Effective filesystem governs which Disks rows surface: Impermanence needs
  # native snapshots, so it is hidden for ext4 / xfs (ADR 0040).
  local fs; fs="$(cfgstate_get "$state" filesystem)"
  [[ -n "$fs" ]] || fs="zfs"
  for spec in "${_MENU_FIELDS[@]}"; do
    IFS='|' read -r section path label default <<<"$spec"
    if [[ "$path" == "options.impermanence.enabled" \
          && ( "$fs" == "ext4" || "$fs" == "xfs" ) ]]; then
      continue
    fi
    value="$(cfgstate_get "$state" "$path")"
    [[ -n "$value" ]] || value="$default"
    if cfgstate_is_overridden "$state" "$path"; then
      overridden=true
    else
      overridden=false
    fi
    rows+=("$(jq -n \
      --arg s "$section" --arg f "$path" --arg l "$label" \
      --arg v "$value" --argjson o "$overridden" \
      '{section:$s, field:$f, label:$l, value:$v, overridden:$o}')")
  done
  printf '%s\n' "${rows[@]}" | jq -s '.'
}
