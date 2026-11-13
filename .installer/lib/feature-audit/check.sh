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
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016
# shellcheck source=../config/config-state.sh
declare -F config_state_get_json >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/config-state.sh"
_check_on() {
  [[ " ${FEATURE_AUDIT_CHECKS:-$FA_CHECK_FAMILIES} " == *" $1 "* ]]
}
FA_CHECK_FAMILIES="manifest features programs binds phases noise"
# The ids of the variants that are not guided.
_FA_PLAIN_VARIANTS='.variants[] | select(.guided | not) | .id'
# _check_manifest — every variant resolves to a valid Effective Config.
_check_manifest() {
  local manifest id config error
  local duplicates='.variants | group_by(.id)[] | select(length > 1) | .[0].id'
  local no_reason='.unverifiable[]? | select((.reason // "") == "")'
  no_reason+=' | "manifest: unverifiable \(.feature) has no reason"'
  local guided='.variants[] | select(.id == $id) | .guided'
  manifest="$(feature_audit_manifest_json)" \
    || { echo "manifest: not valid JSONC"; return; }
  while IFS= read -r id; do echo "manifest: duplicate variant id $id"
  # The ids used by more than one variant.
  done < <(printf '%s\n' "$manifest" | jq -r "$duplicates")
  # An unverifiable entry without a reason.
  printf '%s\n' "$manifest" | jq -r "$no_reason"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    # The variant is a guided one.
    if printf '%s\n' "$manifest" | jq -e --arg id "$id" "$guided" >/dev/null
    then
      continue   # guided variants resolve in-guest from the menu answers
    fi
    if ! config="$(feature_audit_variant_config "$id" 2>/dev/null)" \
      || [[ -z "$config" ]]; then
      echo "manifest: variant $id does not resolve"
      continue
    fi
    if ! error="$(feature_audit_validate_config "$config" 2>&1)"; then
      echo "manifest: variant $id fails validation:" \
        "$(printf '%s\n' "$error" | head -n 1)"
    fi
  # The variant ids, each once.
  done < <(printf '%s\n' "$manifest" | jq -r '.variants | map(.id) | unique[]')
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
    local path default_value role value
    # an empty state renders every field at its default (menu_rows)
    while IFS=$'\t' read -r path default_value; do
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
    # One "field<TAB>default value" line per menu field.
    done < <(menu_rows '{}' '{}' | jq -r '.[] | "\(.field)\t\(.value)"')
  )
}
# _check_config_has <cfg> <path> <value> <default> — the config (menu default
# when absent) holds <value> at <path>; arrays match by membership.
_check_config_has() {
  local held
  local holds='if type == "array" then any(.[]; tostring == $v)'
  holds+=' else tostring == $v end'
  held="$(config_state_get_json "$1" "$2" 2>/dev/null)" || return 1
  # Absent: the menu default, a ", "-joined list.
  [[ "$held" == null ]] && held="$(jq -c -n --arg d "$4" '$d | split(", ")')"
  # The value is the one held, or one of the held list.
  printf '%s\n' "$held" | jq -e --arg v "$3" "$holds" >/dev/null 2>&1
}
# _check_features — every feature value is enabled by some variant, a
# guided variant's `covers`, or an `unverifiable` entry.
_check_features() {
  local manifest id config feature default_value path value
  local covers='(.unverifiable[]?.feature), (.variants[] | .covers[]?)'
  manifest="$(feature_audit_manifest_json)" || return
  local -a configs=()
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    config="$(feature_audit_variant_config "$id" 2>/dev/null)" \
      && configs+=("$config")
  # The non-guided variants' ids.
  done < <(printf '%s\n' "$manifest" | jq -r "$_FA_PLAIN_VARIANTS")
  local covered
  # Every feature an unverifiable entry or a guided variant covers.
  covered="$(printf '%s\n' "$manifest" | jq -r "$covers")"
  while IFS=$'\t' read -r feature default_value; do
    printf '%s\n' "$covered" | grep -qxF "$feature" && continue
    # The path before the first "=", the value after it.
    path="$(printf '%s\n' "$feature" | cut -d= -f1)"
    value="$(printf '%s\n' "$feature" | cut -d= -f2-)"
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
  # The features marked unverifiable.
  covered="$(feature_audit_manifest_json | jq -r '.unverifiable[]?.feature')"
  for program_directory in "$root"/*/*/; do
    [[ -f "$program_directory/config.jsonc" ]] || continue
    name="$(basename "$program_directory")"
    [[ -f "$program_directory/audit.sh" ]] && continue
    printf '%s\n' "$covered" | grep -qxF "program:$name" && continue
    echo "coverage: program $name has no audit probe (audit.sh)"
  done
  # every desktop environment ships a session probe too
  local ext="${FEATURE_AUDIT_EXTRAS_DIR:-$INSTALLER_DIR/extras/desktop}"
  for program_directory in "$ext"/*/; do
    name="$(basename "$program_directory")"
    compgen -G "$program_directory/install-*.jsonc" >/dev/null || continue
    [[ -f "$program_directory/audit.sh" ]] && continue
    printf '%s\n' "$covered" | grep -qxF "desktop:$name" && continue
    echo "coverage: desktop $name has no audit probe (audit.sh)"
  done
}
# _check_binds — every shipped keybind (parsed from the real configs) has
# a declared, testable expectation.
_check_binds() {
  local source_name chord action expected shown
  for source_name in $(feature_audit_binds_sources); do
    expected="$(feature_audit_binds_expect_file "$source_name")"
    # The expectations file exists but is not valid JSONC.
    if [[ -f "$expected" ]] && ! jsonc_strip "$expected" \
      | jq -e . >/dev/null 2>&1
    then
      # The file's path inside the repo (as is when outside it).
      shown="$expected"
      [[ "$expected" == "$FA_REPO_ROOT"/* ]] \
        && shown="${expected:${#FA_REPO_ROOT}+1}"
      echo "coverage: $source_name expectations $shown not valid JSONC"
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
  local desktops='.environment.desktop // []'
  desktops+=' | if type == "string" then [.] else . end | .[]'
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
    # The variant's desktops (a lone desktop counts as one).
    for desktop in $(printf '%s\n' "$config" | jq -r "$desktops"); do
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
  # The non-guided variants' ids.
  done < <(printf '%s\n' "$manifest" | jq -r "$_FA_PLAIN_VARIANTS")
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
  local noise_file manifest ids regex here="${BASH_SOURCE[0]%/*}"
  local regexes='.[]?.regex // empty'
  regexes+=' | if type == "array" then join("") else . end'
  noise_file="$(feature_audit_known_noise_path)"
  [[ -f "$noise_file" ]] || return 0
  manifest="$(feature_audit_manifest_json)" || return 0
  # The manifest's variant ids.
  ids="$(printf '%s\n' "$manifest" | jq -c '[.variants[].id]')"
  # The entries' problems.
  jsonc_strip "$noise_file" \
    | jq -r --argjson ids "$ids" -f "$here/check-noise.jq" 2>/dev/null \
    || echo "noise: not valid JSONC"
  while IFS= read -r regex; do
    R="$regex" awk -f "$here/check-regex.awk" 2>/dev/null \
      || echo "noise: invalid regex $regex"
  # Each entry's regex (parts joined).
  done < <(jsonc_strip "$noise_file" | jq -r "$regexes" 2>/dev/null)
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
  printf '%s\n' "$out" | awk -f "${BASH_SOURCE[0]%/*}/strip-colours.awk"
  return 1
}
