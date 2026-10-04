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
#   fa_audit_check   → Finding lines on stdout; 1 if any
# =============================================================================

_fa_check_on() {
  [[ " ${FEATURE_AUDIT_CHECKS:-$FA_CHECK_FAMILIES} " == *" $1 "* ]]
}

FA_CHECK_FAMILIES="manifest features programs binds phases noise"

# _fa_check_manifest — every variant resolves to a valid Effective Config.
_fa_check_manifest() {
  local m id cfg err
  m="$(fa_manifest_json)" || { echo "manifest: not valid JSONC"; return; }
  jq -r '.variants | group_by(.id)[] | select(length > 1) | .[0].id' <<<"$m" \
    | while IFS= read -r id; do echo "manifest: duplicate variant id $id"; done
  jq -r '.unverifiable[]? | select((.reason // "") == "")
    | "manifest: unverifiable \(.feature) has no reason"' <<<"$m"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if jq -e --arg id "$id" '.variants[] | select(.id == $id) | .guided' \
      <<<"$m" >/dev/null; then
      continue   # guided variants resolve in-guest from the menu answers
    fi
    if ! cfg="$(fa_variant_config "$id" 2>/dev/null)" || [[ -z "$cfg" ]]; then
      echo "manifest: variant $id does not resolve"
      continue
    fi
    if ! err="$(fa_validate_config "$cfg" 2>&1)"; then
      echo "manifest: variant $id fails validation: $(head -1 <<<"$err")"
    fi
  done < <(jq -r '.variants | map(.id) | unique[]' <<<"$m")
}

# Menu fields that are identity/cosmetics, not features (hostname, locales,
# mirrors, pacman look, free text) — outside audit coverage.
_FA_FEATURE_SKIP='^(system\.|__|sysctl$|users$|options\.(mirror_|'
_FA_FEATURE_SKIP+='optional_repos|custom_repositories|pacman\.|age_key_url$))'

# _fa_feature_values — every required `path=value`, derived from the menu's
# own fields + option sets (never a hand list): enum → each option, bool →
# both sides. Storage axes stay with the Combination Matrix (ADR 0046).
_fa_feature_values() {
  (
    # shellcheck source=../config/menu.sh
    source "$INSTALLER_DIR/lib/config/menu.sh"
    # shellcheck source=../matrix/registry.sh
    source "$INSTALLER_DIR/lib/matrix/registry.sh"
    local spec p d role v
    for spec in "${_MENU_FIELDS[@]}"; do
      IFS='|' read -r _ p _ d <<<"$spec"
      [[ "$p" =~ $_FA_FEATURE_SKIP ]] && continue
      role="$(matrix_axis_role "$p" 2>/dev/null || true)"
      [[ "$role" == storage-cluster || "$role" == scalar-sweep ]] && continue
      local -a opts=()
      mapfile -t opts < <(menu_enum_options "$p")
      if ((${#opts[@]})); then
        for v in "${opts[@]}"; do printf '%s=%s\t%s\n' "$p" "$v" "$d"; done
      elif [[ "$d" == true || "$d" == false ]]; then
        printf '%s=true\t%s\n%s=false\t%s\n' "$p" "$d" "$p" "$d"
      fi
    done
  )
}

# _fa_config_has <cfg> <path> <value> <default> — the config (menu default
# when absent) holds <value> at <path>; arrays match by membership.
_fa_config_has() {
  jq -e --arg p "$2" --arg v "$3" --arg d "$4" '
    (getpath($p | split(".")) ) as $x
    | (if $x == null then ($d | split(", ")) else $x end) as $y
    | if ($y | type) == "array" then any($y[]; tostring == $v)
      else ($y | tostring) == $v end' <<<"$1" >/dev/null 2>&1
}

# _fa_check_features — every feature value is enabled by some variant, a
# guided variant's `covers`, or an `unverifiable` entry.
_fa_check_features() {
  local m id cfg feat def p v
  m="$(fa_manifest_json)" || return
  local -a cfgs=()
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    cfg="$(fa_variant_config "$id" 2>/dev/null)" && cfgs+=("$cfg")
  done < <(jq -r '.variants[] | select(.guided | not) | .id' <<<"$m")
  local covered
  covered="$(jq -r '(.unverifiable[]?.feature),
    (.variants[] | .covers[]?)' <<<"$m")"
  while IFS=$'\t' read -r feat def; do
    grep -qxF "$feat" <<<"$covered" && continue
    p="${feat%%=*}"; v="${feat#*=}"
    local hit=0
    for cfg in "${cfgs[@]}"; do
      _fa_config_has "$cfg" "$p" "$v" "$def" && { hit=1; break; }
    done
    ((hit)) || echo "coverage: feature $feat is enabled by no variant"
  done < <(_fa_feature_values)
}

# _fa_check_programs — every registry program ships an audit probe (its
# `audit.sh`), unless the manifest marks `program:<name>` unverifiable.
_fa_check_programs() {
  local root="${FEATURE_AUDIT_PROGRAMS_DIR:-$INSTALLER_DIR/programs}" d n
  local covered
  covered="$(fa_manifest_json | jq -r '.unverifiable[]?.feature')"
  for d in "$root"/*/*/; do
    [[ -f "$d/config.jsonc" ]] || continue
    n="${d%/}"; n="${n##*/}"
    [[ -f "$d/audit.sh" ]] && continue
    grep -qxF "program:$n" <<<"$covered" && continue
    echo "coverage: program $n has no audit probe (audit.sh)"
  done
  # every desktop environment ships a session probe too
  local ext="${FEATURE_AUDIT_EXTRAS_DIR:-$INSTALLER_DIR/extras/desktop}"
  for d in "$ext"/*/; do
    n="${d%/}"; n="${n##*/}"
    compgen -G "$d/install-*.jsonc" >/dev/null || continue
    [[ -f "$d/audit.sh" ]] && continue
    grep -qxF "desktop:$n" <<<"$covered" && continue
    echo "coverage: desktop $n has no audit probe (audit.sh)"
  done
}

# _fa_check_binds — every shipped keybind (parsed from the real configs) has
# a declared, testable expectation.
_fa_check_binds() {
  local src chord action exp
  for src in $(fa_binds_sources); do
    exp="$(fa_binds_expect_file "$src")"
    if [[ -f "$exp" ]] && ! jsonc_strip "$exp" | jq -e . >/dev/null 2>&1
    then
      echo "coverage: $src expectations ${exp#"$FA_REPO_ROOT"/} not valid JSONC"
      continue
    fi
    while IFS=$'\t' read -r _ chord action; do
      [[ -n "$chord" ]] || continue
      echo "coverage: $src bind $chord ($action) has no audit expectation"
    done < <(fa_binds_untested "$src" 2>&1)
  done
}

# _fa_check_phases — Variant Phases name real phases, and skipping never
# loses coverage: every phase, every installed desktop's binds and every
# selected program's probe still run in some variant.
_fa_check_phases() {
  local m id ph p cfg de
  local root="${FEATURE_AUDIT_PROGRAMS_DIR:-$INSTALLER_DIR/programs}"
  m="$(fa_manifest_json)" || return
  local -A ran=() want_de=() bound_de=() want_prog=() probed=()
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    ph="$(fa_variant_phases "$id")"
    for p in $ph; do
      [[ " $FA_VARIANT_PHASES_ALL " == *" $p "* ]] \
        || echo "manifest: variant $id declares unknown phase $p"
      ran[$p]=1
    done
    cfg="$(fa_variant_config "$id" 2>/dev/null)" || continue
    for de in $(jq -r '.environment.desktop // [] | if type == "string"
        then [.] else . end | .[]' <<<"$cfg"); do
      want_de[$de]=1
      [[ " $ph " == *" keybinds "* ]] && bound_de[$de]=1
    done
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      # only programs that ship a probe have one to run
      compgen -G "$root/*/$p/audit.sh" >/dev/null || continue
      want_prog[$p]=1
      [[ " $ph " == *" probes "* ]] && probed[$p]=1
    done < <(fa_selected_programs "$cfg" 2>/dev/null)
  done < <(jq -r '.variants[] | select(.guided | not) | .id' <<<"$m")
  for p in $FA_VARIANT_PHASES_ALL; do
    [[ -n "${ran[$p]:-}" ]] || echo "coverage: phase $p runs in no variant"
  done
  for de in "${!want_de[@]}"; do
    [[ -n "${bound_de[$de]:-}" ]] \
      || echo "coverage: desktop $de binds run in no variant"
  done
  for p in "${!want_prog[@]}"; do
    [[ -n "${probed[$p]:-}" ]] \
      || echo "coverage: program $p probed in no variant"
  done | sort
}

# _fa_check_noise — every Known Noise entry has a valid regex and a reason, and
# its optional variants scope names real manifest variants.
_fa_check_noise() {
  local f m ids re
  f="$(fa_known_noise_path)"
  [[ -f "$f" ]] || return 0
  m="$(fa_manifest_json)" || return 0
  ids="$(jq -c '[.variants[].id]' <<<"$m")"
  jsonc_strip "$f" | jq -r --argjson ids "$ids" '
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
  while IFS= read -r re; do
    # the report matches with awk, so awk judges the regex (bad one: exit 2)
    # via ENVIRON: awk -v would process the regex's backslash escapes
    R="$re" awk 'BEGIN { if ("" ~ ENVIRON["R"]) {} }' 2>/dev/null \
      || echo "noise: invalid regex $re"
  done < <(jsonc_strip "$f" | jq -r '.[]?.regex // empty
    | if type == "array" then join("") else . end' 2>/dev/null)
}

fa_audit_check() {
  local out
  out="$(
    _fa_check_on manifest && _fa_check_manifest
    _fa_check_on features && _fa_check_features
    _fa_check_on programs && _fa_check_programs
    _fa_check_on binds && _fa_check_binds
    _fa_check_on phases && _fa_check_phases
    _fa_check_on noise && _fa_check_noise
    true
  )"
  [[ -z "$out" ]] && return 0
  printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g'
  return 1
}
