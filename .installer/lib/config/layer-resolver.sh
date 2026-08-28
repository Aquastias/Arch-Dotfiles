#!/usr/bin/env bash
# =============================================================================
# lib/config/layer-resolver.sh — Layer Resolver (ADR 0057)
# =============================================================================
# One pure function: given Host Core + a host profile (or User Core + a user
# profile), what is the effective set? JSON in, JSON out — no filesystem, TTY,
# or globals.
#
# The merge rule is per-key, not global — a global rule broke either way (core
# ["lts"] + host ["zen"] built BOTH kernels when concatenating; array-replace
# made the guided menu show a different set from what installed):
#   Additive — concat, dedupe, `exclude` subtracts. Order irrelevant; a lower
#              layer contributing is a feature.
#   Replace  — later layer wins outright. Position carries meaning (element 0 =
#              Primary Kernel / default locale) or the value is a single choice.
# Layers fold in order, LAST wins — a host re-adds what a lower layer excluded.
#
# Public API:
#   layer_resolve_host <core-json> <profile-json>  → effective host JSON
#   layer_resolve_user <core-json> <profile-json>  → effective user JSON
#   layer_resolve <kind> <json...>                 → fold N layers in order
#   layer_additive_keys <host|user>                → the classification table
#   layer_replace_keys  <host|user>                → (for tests + docs)
# =============================================================================

# ── the classification table ────────────────────────────────────────────────
# Additive keys, as jq paths. `packages.repo.*` / `packages.aur.*` mean "every
# category under this object is an additive array".
_LAYER_ADDITIVE_host=(
  "packages.repo.*" "packages.aur.*"
  "host_programs"
  "users"
  "persist.directories" "persist.files"
  "sysctl"                      # deep merge (object of scalars)
)
_LAYER_ADDITIVE_user=(
  "groups" "programs" "ssh_authorized_keys"
)

# Replace keys. The impl treats "not additive" as replace; this table exists for
# docs + the coverage test, so an unlisted key can't silently concatenate.
_LAYER_REPLACE_host=(
  "options.kernel"              # element 0 is the Primary Kernel
  "system.locale" "system.keymap"   # element 0 is the default
  "environment.desktop" "environment.gpu"
  "options.mirror_countries"    # ordered preference
  "storage_groups" "data_pools" # positional
)
_LAYER_REPLACE_user=( "shell" "sudo" "user_services" "git" )

layer_additive_keys() {
  case "$1" in
  host) printf '%s\n' "${_LAYER_ADDITIVE_host[@]}" ;;
  user) printf '%s\n' "${_LAYER_ADDITIVE_user[@]}" ;;
  *) echo "layer_additive_keys: kind must be host|user, got '$1'" >&2
     return 1 ;;
  esac
}
layer_replace_keys() {
  case "$1" in
  host) printf '%s\n' "${_LAYER_REPLACE_host[@]}" ;;
  user) printf '%s\n' "${_LAYER_REPLACE_user[@]}" ;;
  *) echo "layer_replace_keys: kind must be host|user, got '$1'" >&2
     return 1 ;;
  esac
}

# ── the fold ────────────────────────────────────────────────────────────────
# layer_resolve <host|user> <layer-json>... — fold left to right; first is the
# base (core), each next a delta over the result.
layer_resolve() {
  local kind="$1"; shift
  (($#)) || { printf '{}\n'; return 0; }

  local acc="$1"; shift
  local additive
  additive="$(layer_additive_keys "$kind" | jq -R . | jq -s -c .)" \
    || return 1

  local next
  for next in "$@"; do
    acc="$(_layer_fold_one "$acc" "$next" "$additive")" || return 1
  done
  printf '%s\n' "$acc"
}

layer_resolve_host() { layer_resolve host "$1" "$2"; }
layer_resolve_user() { layer_resolve user "$1" "$2"; }

# layer_jq_prelude — shared jq defs so the classification predicate has ONE
# implementation; `guided_core_delta` (Save path, inverse of _layer_fold_one)
# must classify keys identically or the two drift. Needs an $additive binding.
layer_jq_prelude() {
  cat <<'JQ'
    def odedup: reduce .[] as $x ([];
      if any(.[]; . == $x) then . else . + [$x] end);

    # Is <path> (an array of key strings) an additive key? A trailing "*" in a
    # pattern matches exactly one further segment, so "packages.repo.*"
    # matches ["packages","repo","<any category>"].
    def is_additive($path):
      ($path | join(".")) as $flat
      | any($additive[];
          . as $pat
          | if ($pat | endswith(".*"))
            then ($pat | rtrimstr(".*")) as $stem
              | ($path | length) == (($stem | split(".")) | length) + 1
                and ($flat | startswith($stem + "."))
            else . == $flat
            end);
JQ
}

# layer_jq_exclusions — shared jq def for the fold (_layer_fold_one) and the
# guided path (layer_apply_exclusions), so subtract-then-strip has ONE
# implementation. No $additive dependency, so a caller that omits it can still
# include this.
layer_jq_exclusions() {
  cat <<'JQ'
    def _drop($excl): map(select(. as $p | $excl | index($p) | not));
    def _drop_cats($excl): with_entries(.value |=
      (if type == "array" then _drop($excl) else . end));

    # apply_exclusions($pkg; $sys; $usr) — subtract each from its slot, then
    # strip the exclude control keys and prune an emptied packages object.
    def apply_exclusions($pkg_excl; $sys_excl; $usr_excl):
      (if (.packages.repo // null) != null
       then .packages.repo |= _drop_cats($pkg_excl) else . end)
      | (if (.packages.aur // null) != null
         then .packages.aur |= _drop_cats($pkg_excl) else . end)
      | (if (.host_programs // null) != null
         then .host_programs |= _drop($sys_excl) else . end)
      | (if (.programs // null) != null
         then .programs |= _drop($usr_excl) else . end)
      | del(.packages.exclude)
      | del(.host_programs_exclude)
      | del(.programs_exclude)
      | if (.packages // null) == {} then del(.packages) else . end;
JQ
}

# layer_additive_json <host|user> — classification table as a JSON array for
# --argjson additive.
layer_additive_json() { layer_additive_keys "$1" | jq -R . | jq -s -c .; }

# layer_apply_exclusions <config> — apply a config's OWN excludes to itself,
# then strip the control keys. The Guided Effective Config needs this: it never
# goes through a fold (Host Core is already baseline), so without it an
# unchecked package would be installed anyway.
layer_apply_exclusions() {
  # inherit is meaningless without a fold, so drop it up front; apply_exclusions
  # then subtracts the config's OWN excludes and strips the control keys.
  jq "$(layer_jq_exclusions)"'
    del(.packages.inherit)
    | apply_exclusions(
        (.packages.exclude // []);
        (.host_programs_exclude // []);
        (.programs_exclude // []))
  ' <<<"$1"
}

# _layer_fold_one <lower> <upper> <additive-paths-json> — one layer over one.
# Order is deliberate: (1) inherit:false drops lower packages + host_programs,
# (2) additive
# keys concat+dedupe / everything else replaces (recursing into plain objects so
# a nested scalar override keeps its siblings), (3) exclusions apply last. See
# the numbered steps below.
_layer_fold_one() {
  local lower="$1" upper="$2" additive="$3"

  jq -n \
    --argjson lower "$lower" \
    --argjson upper "$upper" \
    --argjson additive "$additive" \
    "$(layer_jq_prelude)$(layer_jq_exclusions)"'
    def merge($a; $b; $path):
      if   ($a == null) then $b
      elif ($b == null) then $a
      elif ($a | type) == "object" and ($b | type) == "object"
        then reduce (($a + $b) | keys_unsorted | unique[]) as $k
          ({}; .[$k] = merge($a[$k]; $b[$k]; $path + [$k]))
      elif ($a | type) == "array" and ($b | type) == "array"
        then if is_additive($path) then (($a + $b) | odedup) else $b end
      else $b
      end;

    # 1. inherit:false drops the lower layer base software wholesale — both
    #    packages AND host_programs (the ADR 0089 base programs are the same
    #    workstation base as the packages, so a bare install opts out of both
    #    with the one flag). Compared to `false` directly: jq `//` treats
    #    false as empty, so `(.inherit // true)` fails.
    (if ($upper.packages.inherit == false)
     then ($lower | del(.packages) | del(.host_programs))
     else $lower end) as $base

    # 2. fold, then strip the control keys so they never reach a consumer.
    | merge($base; $upper; [])
    | del(.packages.inherit)

    # 3. exclusions over the merged result — UPPER layer only. A lower layer
    #    excluding what it never inherited is vacuous, and applying it here
    #    would block a later layer re-adding it, breaking "last layer wins".
    #    apply_exclusions also strips control keys (re-read from the authored
    #    layers next fold — how a later layer re-adds an excluded entry).
    | apply_exclusions(
        ($upper.packages.exclude // []);
        ($upper.host_programs_exclude // []);
        ($upper.programs_exclude // []))
  '
}
