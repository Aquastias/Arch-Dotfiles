#!/usr/bin/env bash
# =============================================================================
# lib/layout/common.sh — shared Layout Module helpers
# =============================================================================
# Sourced by layout-single.sh and layout-multi.sh.
# Requires: lib/common.sh already sourced (provides cfgo, error).
# =============================================================================

# Reads .options.esp_size from Install Config. Returns "512M" when unset.
layout_resolve_esp_size() {
  install_config_esp_size
}

# Converts a size string ("512M", "80G", "2T") to integer GiB, rounded up.
parse_size_to_gib() {
  local raw="${1^^}"
  local num="${raw//[^0-9]/}"
  local unit="${raw//[0-9]/}"
  case "$unit" in
  M | MIB) echo $(((num + 1023) / 1024)) ;;
  G | GIB) echo "$num" ;;
  T | TIB) echo $((num * 1024)) ;;
  *) error "Cannot parse size string: '$1'" ;;
  esac
}

# Asserts layout_plan() published the normalized record: the OS pool name and at
# least one ESP partition (ESP paths are now resolved at plan time, ADR 0034).
# Call at end of layout_plan().
_layout_verify_plan_contract() {
  [[ -n "$LAYOUT_OS_POOL_NAME" ]] ||
    error "Layout contract: LAYOUT_OS_POOL_NAME must be non-empty" \
          "after layout_plan()"
  ((${#LAYOUT_ESP_PARTS[@]} >= 1)) ||
    error "Layout contract: LAYOUT_ESP_PARTS must have ≥1 element" \
          "after layout_plan()"
}

# Asserts layout_partition() populated LAYOUT_ESP_PARTS.
# Call at end of every layout_partition().
_layout_verify_partition_contract() {
  ((${#LAYOUT_ESP_PARTS[@]} >= 1)) ||
    error "Layout contract: LAYOUT_ESP_PARTS must have ≥1 element" \
          "after layout_partition()"
}

# =============================================================================
# Layout phase lifecycle (ADR 0016)
# =============================================================================
# Single ordinal counter + two guards enforce seam-verb ordering. Adapters
# bracket each verb with _layout_enter_phase / _layout_exit_phase. Out-of-order
# calls abort via error before any destructive operation runs.
#
# Phase map (private): validate=1, plan=2, partition=3, pools=4, esp=5.
# Seeded to 0 — the first callable phase is `validate` (ADR 0014).
_LAYOUT_PHASE=0

_layout_phase_ordinal() {
  case "$1" in
  validate)  echo 1 ;;
  plan)      echo 2 ;;
  partition) echo 3 ;;
  pools)     echo 4 ;;
  esp)       echo 5 ;;
  *) error "Unknown layout phase name: '$1'" ;;
  esac
}

_layout_enter_phase() {
  local name="$1" ord
  ord="$(_layout_phase_ordinal "$name")"
  (( _LAYOUT_PHASE == ord - 1 )) ||
    error "Layout phase '$name' out of order:" \
          "_LAYOUT_PHASE=$_LAYOUT_PHASE, expected $((ord - 1))"
}

_layout_exit_phase() {
  local name="$1" ord
  ord="$(_layout_phase_ordinal "$name")"
  _LAYOUT_PHASE="$ord"
}

# The unified layout_plan verb + ESP resolution + leftover-disk adapter live in
# plan.sh; the mode adapters (single/multi) supply _layout_plan_mode and
# _layout_os_disks. Sourced last so the contract/phase helpers above are defined.
# shellcheck source=./plan.sh
source "${BASH_SOURCE[0]%/*}/plan.sh"
