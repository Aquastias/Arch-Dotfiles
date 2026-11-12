#!/usr/bin/env bash
# =============================================================================
# lib/packages/package-resolver-layers.sh — Package Resolver layer provenance
# =============================================================================
# Tags each authored package (packages.repo / packages.aur) with the layer
# that declares it — fleet, core or host — so the report answers "which
# layer do I edit?".
#
# Used by: lib/packages/package-resolver.sh (sources it; uses its
# _package_resolver_emit / _package_resolver_jq / _package_resolver_has_line).
# =============================================================================

# _package_resolver_authored_slots <config> — packages.repo / packages.aur.
# Layer provenance: an authored package the Fleet Layer declares is tagged
# `fleet`, one Host Core declares `core`, otherwise `host` — so the report
# answers "which layer do I edit?" rather than only "was this authored or
# derived?".
_package_resolver_authored_slots() {
  local config="$1" layers_json
  layers_json="$(_package_resolver_layers_json)"
  local slot json package
  for slot in repo aur; do
    json="$(_package_resolver_jq "$config" ".packages.${slot} // {} | tojson")"
    [[ -n "$json" && "$json" != "null" ]] || continue
    while IFS= read -r package; do
      [[ -n "$package" ]] || continue
      _package_resolver_emit "$slot" \
        "$(_package_resolver_authored_layer "$layers_json" "$slot" \
          "$package")" "$package"
    done < <(categorized_list_parse "$json" string \
      "packages.${slot}" 2>/dev/null)
  done
}

# _package_resolver_layers_json — {fleet, core} as one JSON object, each the
# layer's profile (null when unreadable); `{}` when no INSTALLER_DIR is set.
_package_resolver_layers_json() {
  [[ -n "${INSTALLER_DIR:-}" ]] || { printf '{}'; return 0; }
  local layer file json layer_profiles='{}'
  for layer in fleet core; do
    file="${INSTALLER_DIR}/hosts/${layer}/profile.jsonc"
    [[ -f "$file" ]] || continue
    json="$(jsonc_strip "$file" 2>/dev/null)" || continue
    # The object so far, with this layer's profile added under its name.
    layer_profiles="$(printf '%s\n' "$layer_profiles" \
      | jq -c --arg l "$layer" --argjson j "$json" '.[$l] = $j')"
  done
  printf '%s' "$layer_profiles"
}

# _package_resolver_authored_layer <layers-json> <slot> <package> — the first
# layer (fleet, then core) declaring <package> in <slot>, else `host`;
# `authored` when no layer is readable.
_package_resolver_authored_layer() {
  local layers_json="$1" slot="$2" package="$3"
  [[ "$layers_json" != "{}" ]] || { printf 'authored'; return 0; }
  local layer listed
  for layer in fleet core; do
    # Every package the layer lists in <slot>, over all its categories.
    listed="$(printf '%s\n' "$layers_json" \
      | jq -r --arg l "$layer" --arg s "$slot" \
        '(.[$l].packages[$s] // {})[][]')"
    if _package_resolver_has_line "$listed" "$package"; then
      printf '%s\n' "$layer"
      return 0
    fi
  done
  printf 'host\n'
}
