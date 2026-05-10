#!/usr/bin/env bash
# =============================================================================
# lib/layout-common.sh — shared Layout Module helpers
# =============================================================================
# Sourced by layout-single.sh and layout-multi.sh.
# Requires: lib/common.sh already sourced (provides cfgo, error).
# =============================================================================

# Reads .options.esp_size from Install Config. Returns "512M" when unset.
layout_resolve_esp_size() {
  local sz
  sz="$(cfgo '.options.esp_size')"
  printf '%s' "${sz:-512M}"
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

# Asserts layout_plan() set the OS pool name. Call at end of every layout_plan().
_layout_verify_plan_contract() {
  [[ -n "$LAYOUT_OS_POOL_NAME" ]] ||
    error "Layout contract: LAYOUT_OS_POOL_NAME must be non-empty after layout_plan()"
}

# Asserts layout_partition() populated LAYOUT_ESP_PARTS. Call at end of every layout_partition().
_layout_verify_partition_contract() {
  ((${#LAYOUT_ESP_PARTS[@]} >= 1)) ||
    error "Layout contract: LAYOUT_ESP_PARTS must have ≥1 element after layout_partition()"
}
