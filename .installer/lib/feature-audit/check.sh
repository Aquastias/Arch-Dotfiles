#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/check.sh — manifest + coverage checks (ADR 0152)
# =============================================================================
# Pure: no VM. Each problem is one Finding line on stdout. Coverage gaps are
# Findings on purpose: a new program, feature or keybind without audit
# coverage fails the audit instead of silently going untested.
#
# FEATURE_AUDIT_CHECKS (space list, default all) selects check families, so
# tests can exercise one family against fixture data.
#
# Public API:
#   feature_audit_check_variant   → Finding lines on stdout; 1 if any
#
# Used by: tools/feature-audit.sh (check).
# =============================================================================

_check_on() {
  [[ " ${FEATURE_AUDIT_CHECKS:-$FA_CHECK_FAMILIES} " == *" $1 "* ]]
}

FA_CHECK_FAMILIES="manifest features programs binds phases noise"

# _check_manifest — every variant resolves to a valid Effective Config.
_check_manifest() {
  local manifest id config error
  manifest="$(feature_audit_manifest_json)" \
    || { echo "manifest: not valid JSONC"; return; }
  jq -r '.variants | group_by(.id)[] | select(length > 1) | .[0].id' \
    <<<"$manifest" \
    | while IFS= read -r id; do echo "manifest: duplicate variant id $id"; done
  jq -r '.unverifiable[]? | select((.reason // "") == "")
    | "manifest: unverifiable \(.feature) has no reason"' <<<"$manifest"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if jq -e --arg id "$id" '.variants[] | select(.id == $id) | .guided' \
      <<<"$manifest" >/dev/null; then
      continue   # guided variants resolve in-guest from the menu answers
    fi
    if ! config="$(feature_audit_variant_config "$id" 2>/dev/null)" \
      || [[ -z "$config" ]]; then
      echo "manifest: variant $id does not resolve"
      continue
    fi
    if ! error="$(feature_audit_validate_config "$config" 2>&1)"; then
      echo "manifest: variant $id fails validation:" \
        "$(awk 'NR == 1 { print; exit }' <<<"$error")"
    fi
  done < <(jq -r '.variants | map(.id) | unique[]' <<<"$manifest")
}

# Menu fields that are identity/cosmetics, not features (hostname, locales,
# mirrors, pacman look, free text) — outside audit coverage.
_FA_FEATURE_SKIP='^(system\.|__|sysctl$|users$|options\.(mirror_|'
_FA_FEATURE_SKIP+='optional_repos|custom_repositories|pacman\.|age_key_url$))'

# _check_feature_values — every required `path=value`, derived from the menu's
# own fields + option sets (never a hand list): enum → each option, bool →
# both sides. Storage axes stay with the Combination Matrix (ADR 0046).
_check_feature_values() {
  (
    # shellcheck source=../config/menu.sh
    source "$INSTALLER_DIR/lib/config/menu.sh"
    # shellcheck source=../matrix/registry.sh
    source "$INSTALLER_DIR/lib/matrix/registry.sh"
    local spec path default_value role value
    for spec in "${_MENU_FIELDS[@]}"; do
      IFS='|' read -r _ path _ default_value <<<"$spec"
      [[ "$path" =~ $_FA_FEATURE_SKIP ]] && continue
      role="$(matrix_axis_role "$path" 2>/dev/null || true)"
      [[ "$role" == storage-cluster || "$role" == scalar-sweep ]] && continue
      local -a options=()
      mapfile -t options < <(menu_enum_options "$path")
      if ((${#options[@]})); then
        for value in "${options[@]}"; do printf '%s=%s\t%s\n' "$path" \
          "$value" "$default_value"; done
      elif [[ "$default_value" == true || "$default_value" == false ]]; then
        printf '%s=true\t%s\n%s=false\t%s\n' "$path" "$default_value" \
          "$path" "$default_value"
      fi
    done
  )
}

# _check_config_has <cfg> <path> <value> <default> — the config (menu default
# when absent) holds <value> at <path>; arrays match by membership.
_check_config_has() {
  jq -e --arg p "$2" --arg v "$3" --arg d "$4" '
    (getpath($p | split(".")) ) as $x
    | (if $x == null then ($d | split(", ")) else $x end) as $y
    | if ($y | type) == "array" then any($y[]; tostring == $v)
      else ($y | tostring) == $v end' <<<"$1" >/dev/null 2>&1
}

# _check_features — every feature value is enabled by some variant, a
# guided variant's `covers`, or an `unverifiable` entry.
_check_features() {
  local manifest id config feature default_value path value
  manifest="$(feature_audit_manifest_json)" || return
  local -a configs=()
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    config="$(feature_audit_variant_config "$id" 2>/dev/null)" \
      && configs+=("$config")
  done < <(jq -r '.variants[] | select(.guided | not) | .id' <<<"$manifest")
  local covered
  covered="$(jq -r '(.unverifiable[]?.feature),
    (.variants[] | .covers[]?)' <<<"$manifest")"
  while IFS=$'\t' read -r feature default_value; do
    grep -qxF "$feature" <<<"$covered" && continue
    path="${feature%%=*}"; value="${feature#*=}"
    local hit=0
    for config in "${configs[@]}"; do
      _check_config_has "$config" "$path" "$value" "$default_value" \
        && { hit=1; break; }
    done
    ((hit)) || echo "coverage: feature $feature is enabled by no variant"
  done < <(_check_feature_values)
}

# _check_programs — every registry program ships an audit probe (its
# `audit.sh`), unless the manifest marks `program:<name>` unverifiable.
_check_programs() {
  local root="${FEATURE_AUDIT_PROGRAMS_DIR:-$INSTALLER_DIR/programs}" \
    program_directory name
  local covered
  covered="$(feature_audit_manifest_json | jq -r '.unverifiable[]?.feature')"
  for program_directory in "$root"/*/*/; do
    [[ -f "$program_directory/config.jsonc" ]] || continue
    name="${program_directory%/}"; name="${name##*/}"
    [[ -f "$program_directory/audit.sh" ]] && continue
    grep -qxF "program:$name" <<<"$covered" && continue
    echo "coverage: program $name has no audit probe (audit.sh)"
  done
  # every desktop environment ships a session probe too
  local ext="${FEATURE_AUDIT_EXTRAS_DIR:-$INSTALLER_DIR/extras/desktop}"
  for program_directory in "$ext"/*/; do
    name="${program_directory%/}"; name="${name##*/}"
    compgen -G "$program_directory/install-*.jsonc" >/dev/null || continue
    [[ -f "$program_directory/audit.sh" ]] && continue
    grep -qxF "desktop:$name" <<<"$covered" && continue
    echo "coverage: desktop $name has no audit probe (audit.sh)"
  done
}

# _check_binds — every shipped keybind (parsed from the real configs) has
# a declared, testable expectation.
_check_binds() {
  local source_name chord action expected
  for source_name in $(feature_audit_binds_sources); do
    expected="$(feature_audit_binds_expect_file "$source_name")"
    if [[ -f "$expected" ]] && ! jsonc_strip "$expected" \
      | jq -e . >/dev/null 2>&1
    then
      echo \
        "coverage: $source_name expectations" \
        "${expected#"$FA_REPO_ROOT"/} not valid JSONC"
      continue
    fi
    while IFS=$'\t' read -r _ chord action; do
      [[ -n "$chord" ]] || continue
      echo \
        "coverage: $source_name bind $chord ($action) has no audit expectation"
    done < <(feature_audit_binds_untested "$source_name" 2>&1)
  done
}

# _check_phases — Variant Phases name real phases, and skipping never
# loses coverage: every phase, every installed desktop's binds and every
# selected program's probe still run in some variant.
_check_phases() {
  local manifest id phases name config desktop
  local root="${FEATURE_AUDIT_PROGRAMS_DIR:-$INSTALLER_DIR/programs}"
  manifest="$(feature_audit_manifest_json)" || return
  local -A ran=() wanted_desktops=() bound_desktops=() wanted_programs=() \
    probed=()
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    phases="$(feature_audit_variant_phases "$id")"
    for name in $phases; do
      [[ " $FA_VARIANT_PHASES_ALL " == *" $name "* ]] \
        || echo "manifest: variant $id declares unknown phase $name"
      ran[$name]=1
    done
    config="$(feature_audit_variant_config "$id" 2>/dev/null)" || continue
    for desktop in $(jq -r '.environment.desktop // [] | if type == "string"
        then [.] else . end | .[]' <<<"$config"); do
      wanted_desktops[$desktop]=1
      [[ " $phases " == *" keybinds "* ]] && bound_desktops[$desktop]=1
    done
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      # only programs that ship a probe have one to run
      compgen -G "$root/*/$name/audit.sh" >/dev/null || continue
      wanted_programs[$name]=1
      [[ " $phases " == *" probes "* ]] && probed[$name]=1
    done < <(feature_audit_selected_programs "$config" 2>/dev/null)
  done < <(jq -r '.variants[] | select(.guided | not) | .id' <<<"$manifest")
  for name in $FA_VARIANT_PHASES_ALL; do
    [[ -n "${ran[$name]:-}" ]] \
      || echo "coverage: phase $name runs in no variant"
  done
  for desktop in "${!wanted_desktops[@]}"; do
    [[ -n "${bound_desktops[$desktop]:-}" ]] \
      || echo "coverage: desktop $desktop binds run in no variant"
  done
  for name in "${!wanted_programs[@]}"; do
    [[ -n "${probed[$name]:-}" ]] \
      || echo "coverage: program $name probed in no variant"
  done | sort
}

# _check_noise — every Known Noise entry has a valid regex and a reason, and
# its optional variants scope names real manifest variants.
_check_noise() {
  local noise_file manifest ids regex
  noise_file="$(feature_audit_known_noise_path)"
  [[ -f "$noise_file" ]] || return 0
  manifest="$(feature_audit_manifest_json)" || return 0
  ids="$(jq -c '[.variants[].id]' <<<"$manifest")"
  jsonc_strip "$noise_file" | jq -r --argjson ids "$ids" '
    if type != "array" then "noise: not a JSON array" else .[] |
      (.regex // "?" | if type == "array" then join("") else . end) as $r |
      (if (.reason // "") == "" then "noise: \($r) has no reason"
       else empty end),
      (if .variants == null then empty
       elif (.variants | type) != "array"
       then "noise: \($r) variants not an array"
       else .variants[] | select(. as $v | $ids | index($v) | not)
         | "noise: \($r) names unknown variant \(.)" end)
    end' 2>/dev/null || echo "noise: not valid JSONC"
  while IFS= read -r regex; do
    # the report matches with awk, so awk judges the regex (bad one: exit 2)
    # via ENVIRON: awk -v would process the regex's backslash escapes
    R="$regex" awk 'BEGIN { if ("" ~ ENVIRON["R"]) {} }' 2>/dev/null \
      || echo "noise: invalid regex $regex"
  done < <(jsonc_strip "$noise_file" | jq -r '.[]?.regex // empty
    | if type == "array" then join("") else . end' 2>/dev/null)
}

feature_audit_check_variant() {
  local out
  out="$(
    _check_on manifest && _check_manifest
    _check_on features && _check_features
    _check_on programs && _check_programs
    _check_on binds && _check_binds
    _check_on phases && _check_phases
    _check_on noise && _check_noise
    true
  )"
  [[ -z "$out" ]] && return 0
  printf '%s\n' "$out" | awk '{ gsub(/\033\[[0-9;]*m/, ""); print }'
  return 1
}
