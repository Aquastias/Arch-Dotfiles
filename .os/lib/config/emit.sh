#!/usr/bin/env bash
# =============================================================================
# lib/config/emit.sh — Guided Installer Emitter (ADR 0039)
# =============================================================================
# Turns a Config State (the sparse override map) plus an optional disk
# assignment into the device-baked **Effective Config** the back-end consumes —
# the same artifact the Pre-Install Picker produces. The override map is merged
# *over Host Core* (so the shared base — cups, swappiness, base users — still
# applies), then the picked disks are baked onto the layout skeleton.
#
# Pure: reads OS_DIR's Host Core, no disk writes, JSON on stdout.
# Requires OS_DIR set.
#
# Public API:
#   emit_effective <state> <assignment>  → device-baked Effective Config
# =============================================================================

# shellcheck source=./state.sh
[[ "$(type -t cfgstate_emit)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/state.sh"
# shellcheck source=./layers.sh
[[ "$(type -t _configs_merge)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/layers.sh"
# shellcheck source=../picker.sh
[[ "$(type -t picker_assign_disks)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"

# guided_user_profile <form> — author a User Profile delta (issue 07) from an
# ad-hoc user form. Drops the `name` key (the directory basename is the username,
# ADR 0036) and prunes empty values (empty string, empty array, `false`, null)
# so the result is a sparse delta over User Core — only what the operator set,
# closed-schema-valid. Pure: form JSON in → profile JSON out.
guided_user_profile() {
  jq -c '
    del(.name)
    | with_entries(select(
        (.value != null) and (.value != "") and (.value != false)
        and (.value != []) and (.value != {})))
  ' <<<"$1"
}

# emit_promote_programs <config> — the program-promotion split (issue 06).
# A typed packages.extra name that resolves to a programs/<cat>/<name>/ with
# system:true is moved into system_programs (installed via the Program Runner);
# non-matches and system:false (user) programs stay repo packages. A name that
# is also a real repo package resolves as the program (program wins). Resolution
# is TUI-side only — the back-end's System-Program-vs-package contract is
# untouched. Pure: reads OS_DIR's programs tree + the config arg. No extras →
# the config is returned unchanged.
emit_promote_programs() {
  local config="$1"
  local -a extras
  mapfile -t extras < <(jq -r '.packages.extra[]? // empty' <<<"$config")
  ((${#extras[@]})) || { printf '%s\n' "$config"; return 0; }

  configs_build_registry >/dev/null 2>&1 || true
  local -a promote=() keep=()
  local name rel is_sys
  for name in "${extras[@]}"; do
    [[ -n "$name" ]] || continue
    if rel="$(resolve_program "$name" 2>/dev/null)" \
       && is_sys="$(_configs_parse "${OS_DIR}/programs/${rel}/config.jsonc" \
            2>/dev/null | jq -r '.system // false')" \
       && [[ "$is_sys" == "true" ]]; then
      promote+=("$name")
    else
      keep+=("$name")
    fi
  done

  local promote_json keep_json
  promote_json="$(_emit_json_array "${promote[@]}")"
  keep_json="$(_emit_json_array "${keep[@]}")"
  # Existing system_programs first, then promoted (order-preserving dedup);
  # packages.extra rewritten to the kept names.
  jq -c --argjson promote "$promote_json" --argjson keep "$keep_json" '
    def odedup: reduce .[] as $x ([];
      if any(.[]; . == $x) then . else . + [$x] end);
    .system_programs = (((.system_programs // []) + $promote) | odedup)
    | .packages.extra = $keep
  ' <<<"$config"
}

# _emit_json_array <item...> — a JSON string array of the args ([] when none).
_emit_json_array() {
  (($#)) || { printf '[]'; return 0; }
  printf '%s\n' "$@" | jq -R . | jq -s -c .
}

# emit_effective <state> <assignment> — Effective Config on stdout.
# Merges the state's override map over Host Core, then bakes the assignment's
# picked disks onto the layout skeleton (reusing the picker's assembler).
emit_effective() {
  local state="$1" assignment="$2" overrides core merged
  overrides="$(cfgstate_emit "$state")"
  core="$(_configs_parse "$OS_DIR/hosts/core/profile.jsonc")" || core='{}'
  merged="$(_configs_merge "$core" "$overrides")"
  # Program-promotion split: route typed packages.extra program names into
  # system_programs before the disks are baked (TUI-side; back-end unchanged).
  merged="$(emit_promote_programs "$merged")"
  picker_assign_disks "$merged" "$assignment"
}
