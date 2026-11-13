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
#   layer_resolver_resolve_host <core-json> <profile-json>
#       → effective host JSON
#   layer_resolver_resolve_user <core-json> <profile-json>
#       → effective user JSON
#   layer_resolver_resolve <kind> <json...>
#       → fold N layers in order
#   layer_resolver_additive_keys <host|user> → the classification table
#   layer_resolver_replace_keys  <host|user> → (for tests + docs)
#
# Used by: lib/config/{config-state,emit,profile-loader}.sh, the Guided
# Installer (lib/guided/controller.sh, lib/guided/shell.sh).
# =============================================================================

# ── the classification table ────────────────────────────────────────────────
# Additive keys, as jq paths. `packages.repo.*` / `packages.aur.*` mean "every
# category under this object is an additive array".
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

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

layer_resolver_additive_keys() {
  case "$1" in
  host) printf '%s\n' "${_LAYER_ADDITIVE_host[@]}" ;;
  user) printf '%s\n' "${_LAYER_ADDITIVE_user[@]}" ;;
  *) echo "layer_resolver_additive_keys: kind must be host|user, got '$1'" >&2
     return 1 ;;
  esac
}
layer_resolver_replace_keys() {
  case "$1" in
  host) printf '%s\n' "${_LAYER_REPLACE_host[@]}" ;;
  user) printf '%s\n' "${_LAYER_REPLACE_user[@]}" ;;
  *) echo "layer_resolver_replace_keys: kind must be host|user, got '$1'" >&2
     return 1 ;;
  esac
}

# ── the fold ────────────────────────────────────────────────────────────────
# layer_resolver_resolve <host|user> <layer-json>... — fold left to right; first
# is the base (core), each next a delta over the result.
layer_resolver_resolve() {
  local kind="$1"; shift
  (($#)) || { printf '{}\n'; return 0; }

  local acc="$1"; shift
  local additive
  additive="$(layer_resolver_additive_json "$kind")" || return 1

  local next
  for next in "$@"; do
    acc="$(_layer_resolver_fold_one "$acc" "$next" "$additive")" || return 1
  done
  printf '%s\n' "$acc"
}

layer_resolver_resolve_host() { layer_resolver_resolve host "$1" "$2"; }
layer_resolver_resolve_user() { layer_resolver_resolve user "$1" "$2"; }

# layer_resolver_jq_prelude — shared jq defs so the classification predicate has
# ONE implementation; `emit_core_delta` (Save path, inverse of
# _layer_resolver_fold_one) must classify keys identically or the two drift.
# Needs an $additive binding.
layer_resolver_jq_prelude() {
  cat "${BASH_SOURCE[0]%/*}/layer-resolver-prelude.jq"
}

# layer_resolver_jq_exclusions — shared jq def for the fold
# (_layer_resolver_fold_one) and the guided path
# (layer_resolver_apply_exclusions), so subtract-then-strip has ONE
# implementation. No $additive dependency, so a caller that omits it can still
# include this.
layer_resolver_jq_exclusions() {
  cat "${BASH_SOURCE[0]%/*}/layer-resolver-exclusions.jq"
}

# layer_resolver_additive_json <host|user> — classification table as a JSON
# array for --argjson additive.
layer_resolver_additive_json() {
  local keys list='$keys | split("\n") | map(select(length > 0))'
  keys="$(layer_resolver_additive_keys "$1")" || return 1
  # The additive keys as a JSON array.
  jq -cn --arg keys "$keys" "$list"
}

# layer_resolver_apply_exclusions <config> — apply a config's OWN excludes to
# itself, then strip the control keys. The Guided Effective Config needs this:
# it never goes through a fold (Host Core is already baseline), so without it an
# unchecked package would be installed anyway.
layer_resolver_apply_exclusions() {
  # inherit is meaningless without a fold, so drop it up front; apply_exclusions
  # then subtracts the config's OWN excludes and strips the control keys.
  local apply='del(.packages.inherit) | del(.programs_inherit)'
  apply+=' | apply_exclusions((.packages.exclude // []);'
  apply+=' (.host_programs_exclude // []); (.programs_exclude // []))'
  # The config with its own exclusions applied.
  printf '%s\n' "$1" | jq "$(layer_resolver_jq_exclusions)${apply}"
}

# _layer_resolver_fold_one <lower> <upper> <additive-paths-json> — one layer
# over one. Order is deliberate: (1) inherit:false drops lower packages +
# host_programs, (2) additive keys concat+dedupe / everything else replaces
# (recursing into plain objects so a nested scalar override keeps its siblings),
# (3) exclusions apply last. See the numbered steps below.
_layer_resolver_fold_one() {
  local lower="$1" upper="$2" additive="$3" program
  program="$(layer_resolver_jq_prelude)$(layer_resolver_jq_exclusions)"
  program+="$(cat "${BASH_SOURCE[0]%/*}/layer-resolver-fold.jq")"
  # The upper layer folded over the lower one (layer-resolver-fold.jq).
  jq -n \
    --argjson lower "$lower" \
    --argjson upper "$upper" \
    --argjson additive "$additive" "$program"
}
