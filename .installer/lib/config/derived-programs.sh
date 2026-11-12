#!/usr/bin/env bash
# =============================================================================
# lib/config/derived-programs.sh — fold toggle-derived Host Programs into a
# config
# =============================================================================
# Printing, Bluetooth, Power and Mirrors each derive Host Programs from a menu
# setting (cups, bluetooth, ppd/tuned, reflector). Each injector folds its
# programs into .host_programs the same way, here.
#
# Used by: lib/config/{printing,bluetooth,power,mirrors}.sh.
# =============================================================================

# derived_programs_inject <config-json> <programs> — the config with each of
# <programs> (one per line, distinct) appended to .host_programs when not
# already there, in order. No programs → the config untouched (no empty
# host_programs is added). Pure: JSON in, compact JSON out.
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

derived_programs_inject() {
  local config="$1" programs="$2"
  local inject='($progs | split("\n") | map(select(length > 0))) as $add'
  inject+=' | (.host_programs // []) as $current'
  inject+=' | .host_programs = $current'
  inject+=' + [$add[] | . as $p | select($current | index($p) | not)]'
  if [[ -z "$programs" ]]; then
    # The config, unchanged.
    printf '%s\n' "$config" | jq -c .
    return
  fi
  # The config with the missing programs added.
  printf '%s\n' "$config" | jq -c --arg progs "$programs" "$inject"
}
