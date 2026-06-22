#!/usr/bin/env bash
# =============================================================================
# lib/config/edits.sh — Guided Installer pure edit setters (ADR 0042)
# =============================================================================
# The SET half of every guided editor, extracted into pure functions shared by
# two callers: the replay helpers in lib/guided.sh (which GET a value through
# the selection seam, then SET it) and the persistent-fzf controller (which GETs
# a value from fzf, then SETs it). Centralizing the bespoke jq here means the
# path/value writes have one tested implementation — the controller never
# re-derives them.
#
# Each setter takes a Config State (the sparse override map) plus a raw value
# and prints the new state on stdout. A no-op input (empty / nothing to add)
# prints the state UNCHANGED and returns rc 1, so a caller can `new="$(edit_…)"
# || return 1` to skip a commit. Pure: JSON in/out, no TTY.
# =============================================================================

# shellcheck source=./state.sh
[[ "$(type -t cfgstate_set)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/state.sh"

# edit_set_scalar <state> <path> <str> — a string scalar at a dotted path.
# rc 1 (unchanged) on empty input.
edit_set_scalar() {
  local state="$1" path="$2" v="$3"
  [[ -n "$v" ]] || { printf '%s' "$state"; return 1; }
  cfgstate_set "$state" "$path" "$(jq -n --arg x "$v" '$x')"
}

# edit_set_bool <state> <path> <true|false> — a JSON bool at a dotted path.
# rc 1 (unchanged) when the value is neither literal.
edit_set_bool() {
  local state="$1" path="$2" v="$3"
  [[ "$v" == "true" || "$v" == "false" ]] || { printf '%s' "$state"; return 1; }
  cfgstate_set "$state" "$path" "$v"
}

# edit_set_array <state> <path> <val...> — a JSON string array at a dotted path
# (pick order preserved). rc 1 (unchanged) when nothing is passed.
edit_set_array() {
  local state="$1" path="$2"; shift 2
  (($#)) || { printf '%s' "$state"; return 1; }
  cfgstate_set "$state" "$path" "$(printf '%s\n' "$@" | jq -R . | jq -s -c .)"
}

# edit_set_gpu <state> <val...> — environment.gpu: `auto` is mutually exclusive
# (clears vendors, stores the scalar "auto"); otherwise the vendor list as an
# array. rc 1 (unchanged) when nothing is passed.
edit_set_gpu() {
  local state="$1"; shift
  (($#)) || { printf '%s' "$state"; return 1; }
  local p
  for p in "$@"; do
    [[ "$p" == "auto" ]] \
      && { cfgstate_set "$state" environment.gpu '"auto"'; return 0; }
  done
  cfgstate_set "$state" environment.gpu \
    "$(printf '%s\n' "$@" | jq -R . | jq -s -c .)"
}

# edit_set_sysctl <state> <key> <value> — set/override one sysctl pair. The key
# is a LITERAL object key (a dotted `vm.swappiness` is NOT a nested path), and a
# numeric value is stored as a number. rc 1 (unchanged) on an empty key.
edit_set_sysctl() {
  local state="$1" k="$2" v="$3"
  [[ -n "$k" ]] || { printf '%s' "$state"; return 1; }
  jq --arg k "$k" --arg v "$v" '.sysctl[$k] = ($v | (tonumber? // .))' <<<"$state"
}

# edit_append_packages <state> <raw> — whitespace-split package name(s) appended
# to packages.extra. rc 1 (unchanged) on empty input.
edit_append_packages() {
  local state="$1" raw="$2"
  [[ -n "$raw" ]] || { printf '%s' "$state"; return 1; }
  jq --arg s "$raw" \
    '.packages.extra = ((.packages.extra // [])
      + ($s | split(" ") | map(select(length > 0))))' <<<"$state"
}

# edit_append_system_programs <state> <name...> — dedup-append host System
# Program name(s) to system_programs. rc 1 (unchanged) when nothing is passed.
edit_append_system_programs() {
  local state="$1"; shift
  (($#)) || { printf '%s' "$state"; return 1; }
  jq --argjson add "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
    '.system_programs = ((.system_programs // []) + $add | unique)' <<<"$state"
}

# edit_append_persist <state> <dir> — append one absolute directory to
# persist.directories. rc 1 (unchanged) on empty input.
edit_append_persist() {
  local state="$1" dir="$2"
  [[ -n "$dir" ]] || { printf '%s' "$state"; return 1; }
  jq --arg p "$dir" \
    '.persist.directories = ((.persist.directories // []) + [$p])' <<<"$state"
}

# edit_apply_skeleton <state> <skeleton-json> — drop any previous pool-skeleton
# keys, then merge the new skeleton in (switching layouts never leaves a stale
# group behind).
edit_apply_skeleton() {
  local state="$1" sk="$2"
  jq --argjson sk "$sk" \
    'del(.os_pool, .storage_groups, .data_pools) * $sk' <<<"$state"
}

# edit_set_users <state> <name...> — set .users to the order-preserving dedup of
# the names (users[0] = Primary User). With NO names the key is unset (a host
# may carry no user). Always rc 0 — clearing is a real edit, not a no-op.
edit_set_users() {
  local state="$1"; shift
  if (($# == 0)); then
    cfgstate_unset "$state" users
    return 0
  fi
  cfgstate_set "$state" users "$(printf '%s\n' "$@" | jq -R . | jq -s -c \
    'reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end)')"
}
