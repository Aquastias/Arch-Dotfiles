#!/usr/bin/env bash
# =============================================================================
# lib/config/layer-resolver.sh — Layer Resolver (ADR 0057)
# =============================================================================
# One pure function answering "given Host Core and a host profile, what is the
# effective set?" — and the same for User Core and a user profile.
#
# Two divergent merge rules were in use before this, and BOTH were load-bearing
# where they were:
#   - The config-load path concatenated every array. Harmless only while Host
#     Core was nearly empty; the moment core carries content, a core
#     options.kernel of ["lts"] plus a host wanting ["zen"] yields BOTH, each
#     built against ZFS DKMS.
#   - The guided effective view replaced arrays. Deliberate — it is what lets
#     an operator drop a seeded user or switch kernels — but it meant the menu
#     displayed a different set from what installed.
#
# So the rule cannot be global either way. It is per-key, classified by
# **unordered set versus ordered selection**:
#
#   Additive  — concat, dedupe, and `exclude` subtracts. Membership is what
#               matters, order does not, and a lower layer contributing is a
#               feature.
#   Replace   — the later layer wins outright. Position carries meaning
#               (element 0 is the Primary Kernel / default locale), or the
#               value is a single choice, so merging two layers is incoherent.
#
# Layers fold in order and the LAST layer wins, so a host may re-add something
# a lower layer excluded.
#
# Pure: JSON in, JSON out. No filesystem, no TTY, no globals.
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
  "system_programs"
  "users"
  "persist.directories" "persist.files"
  "sysctl"                      # deep merge (object of scalars)
)
_LAYER_ADDITIVE_user=(
  "groups" "programs" "ssh_authorized_keys"
)

# Replace keys — a later layer wins outright. Listed for documentation and the
# coverage test; the implementation treats "not additive" as replace, so this
# table cannot drift into letting an unlisted key concatenate by accident.
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
# layer_resolve <host|user> <layer-json>... — fold the layers left to right.
# The first is the base (core); each subsequent one is a delta over the result.
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

# _layer_fold_one <lower> <upper> <additive-paths-json> — one layer over one.
#
# Order of operations matters and is deliberate:
#   1. `inherit: false` drops the lower layer's packages FIRST, so a fixture
#      opting out never has to exclude what it never wanted. Scoped to
#      packages only — users and sysctl still inherit.
#   2. Additive keys concat+dedupe; everything else is replaced by the upper
#      layer (recursing into plain objects so a nested scalar override does
#      not wipe its siblings).
#   3. Exclusions apply LAST, over the merged result, so the upper layer's own
#      additions can be excluded by the same layer and — because each fold
#      re-applies the surviving lists — a later layer can re-add something an
#      earlier one excluded.
_layer_fold_one() {
  local lower="$1" upper="$2" additive="$3"

  jq -n \
    --argjson lower "$lower" \
    --argjson upper "$upper" \
    --argjson additive "$additive" '
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

    # 1. packages.inherit: false — drop the lower layer packages wholesale.
    #    Compared against `false` directly: jq'"'"'s `//` treats false as empty,
    #    so `(.inherit // true) == false` is never true.
    (if ($upper.packages.inherit == false)
     then ($lower | del(.packages))
     else $lower end) as $base

    # 2. fold, then strip the control keys so they never reach a consumer.
    | merge($base; $upper; [])
    | del(.packages.inherit)

    # 3. exclusions, applied over the merged result — the UPPER layer only.
    #    A lower layer excluding something it never inherited is vacuous, and
    #    applying it here would stop a later layer from re-adding the entry,
    #    which is exactly the "last layer wins" guarantee.
    | ($upper.packages.exclude // []) as $pkg_excl
    | ($upper.system_programs_exclude // []) as $sys_excl
    | ($upper.programs_exclude // []) as $usr_excl

    | (if (.packages.repo // null) != null
       then .packages.repo |= with_entries(
              .value |= (if type == "array"
                         then map(select(. as $p | $pkg_excl | index($p) | not))
                         else . end))
       else . end)
    | (if (.packages.aur // null) != null
       then .packages.aur |= with_entries(
              .value |= (if type == "array"
                         then map(select(. as $p | $pkg_excl | index($p) | not))
                         else . end))
       else . end)
    | (if (.system_programs // null) != null
       then .system_programs |=
              map(select(. as $p | $sys_excl | index($p) | not))
       else . end)
    | (if (.programs // null) != null
       then .programs |= map(select(. as $p | $usr_excl | index($p) | not))
       else . end)

    # The exclude lists are control keys, not content — drop them so the
    # effective config stays the shape the back-end reads. They are re-read
    # from the authored layers on the next fold, which is what lets a later
    # layer re-add something an earlier layer excluded.
    | del(.packages.exclude)
    | del(.system_programs_exclude)
    | del(.programs_exclude)
    | if (.packages // null) == {} then del(.packages) else . end
  '
}
