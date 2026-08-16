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
declare -F cfgstate_emit >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/state.sh"
# shellcheck source=./layer-resolver.sh
declare -F layer_additive_keys >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/layer-resolver.sh"
# shellcheck source=./layers.sh
declare -F _configs_merge >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/layers.sh"
# shellcheck source=../picker.sh
declare -F picker_assign_disks >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"

# guided_profile_delta <config> — the device-less Host Profile a Save writes
# (issue 08). Strips every device path — the single `.disk` and the per-pool
# `.disks[]` arrays — keeping the mode/topology/disk_count skeleton, so the
# committed artifact never carries operator-picked devices (ADR 0036's invariant)
# yet still re-installs via `install.sh --profile <name>`. Pure: JSON in/out.
guided_profile_delta() {
  jq -c '
    del(.disk)
    | if .os_pool then .os_pool |= del(.disks) else . end
    | if .storage_groups then .storage_groups |= map(del(.disks)) else . end
    | if .data_pools then .data_pools |= map(del(.disks)) else . end
  ' <<<"$1"
}

# guided_core_delta <effective> — the effective config reduced to what it adds
# OVER Host Core, so a saved profile stays layered rather than freezing a
# snapshot (ADR 0056, PRD story 32).
#
# The menu baseline now loads Host Core, so the effective view legitimately
# contains core's whole package list, system programs and sysctl. Writing that
# verbatim would bake ~61 inherited packages into every saved profile and
# silently decouple it from core on the next edit.
#
# The reduction is the inverse of the Layer Resolver's fold, key-class by
# key-class, so `layer_resolve host <core> <delta>` reproduces <effective>:
#   additive array → subtract core's members
#   object         → drop keys whose value core already provides
#   everything else→ drop when identical to core's value
# Pure: JSON in, JSON out.
guided_core_delta() {
  local effective="$1" core="$2" additive
  additive="$(layer_additive_json host)"

  jq -n --argjson eff "$effective" --argjson core "$core" \
        --argjson additive "$additive" "$(layer_jq_prelude)"'
    def prune($e; $c; $path):
      if   ($c == null) then $e
      elif ($e == null) then null
      elif ($e | type) == "object" and ($c | type) == "object"
        then reduce ($e | keys_unsorted[]) as $k
          ({}; . as $acc
           | prune($e[$k]; $c[$k]; $path + [$k]) as $v
           | if $v == null then $acc else $acc + {($k): $v} end)
      elif ($e | type) == "array" and ($c | type) == "array"
        then if is_additive($path)
             # subtracting core leaving nothing means the layer adds nothing
             then ([$e[] | select(. as $x | $c | index($x) | not)]
                   | if length == 0 then null else . end)
             # a replace key is dropped only when IDENTICAL to the core
             # value; an empty array is a deliberate choice (e.g. no
             # desktop) and must survive, not be read as "nothing to say".
             else (if $e == $c then null else $e end)
             end
      else (if $e == $c then null else $e end)
      end;

    prune($eff; $core; [])
    # an object that pruned empty carries no information — drop it
    | walk(if type == "object"
           then with_entries(select((.value | type != "object")
                                    or (.value | length > 0)))
           else . end)
  '
}

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

# _emit_json_array <item...> — a JSON string array of the args ([] when none).
_emit_json_array() {
  (($#)) || { printf '[]'; return 0; }
  printf '%s\n' "$@" | jq -R . | jq -s -c .
}

# emit_effective <state> <assignment> — Effective Config on stdout.
# Bakes the assignment's picked disks onto the layout skeleton (reusing the
# picker's assembler).
#
# Host Core is NOT merged here. It enters once, into the menu's baseline
# (cfgstate_seed_defaults), and the caller passes the effective view — the
# operator's overrides over that baseline. Merging core a second time here is
# precisely the bug where the menu displayed `system programs: grub` while the
# install produced `["cups","grub"]`: display replaced arrays, emit
# concatenated them. One entry point for core means the two cannot disagree.
#
# There is likewise no promotion step. It used to run HERE and only here, so a
# typed package name resolving to a Program became a system_program in the
# guided path while `install.sh --profile` and `install.sh <config-file>` left
# it a raw package. A name is now either a Program or a package, enforced at
# config load by validate_package_program_exclusivity, and the guided
# extra-packages row routes what the operator types at ENTRY time.
emit_effective() {
  local state="$1" assignment="$2" view
  # Apply the operator's own exclusions before baking disks. The Packages
  # screen writes packages.exclude into Config State, but the guided path
  # never goes through a layer fold (core is already in the baseline), so
  # without this an unchecked package would be emitted and installed anyway.
  view="$(layer_apply_exclusions "$(cfgstate_emit "$state")")"
  picker_assign_disks "$view" "$assignment"
}
