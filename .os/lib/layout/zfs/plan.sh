#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/plan.sh — the Layout Planner (pure: no destructive ops, no TTY)
# =============================================================================
# The single `layout_plan` seam verb. It brackets the plan phase (ADR 0016),
# dispatches to the active mode adapter's planning hook (`_layout_plan_mode`,
# which owns the mode-private `_LAYOUT_IMPL_*` state and the pool-name record),
# resolves the ESP partitions from the adapter's ordered OS disks, and verifies
# the plan contract. The destructive verbs (`layout_partition`,
# `layout_create_pools`, `layout_mount_esp`) stay in the mode adapters.
#
# ESP paths are decided here, before any disk is touched: `part_name` is a pure
# string transform, so `<os-disk> + p1` is knowable at plan time. The primary
# OS disk's ESP is index 0.
#
# Any interactive choice the planner needs (the leftover-disk fold-vs-own
# prompt) goes through the Leftover-Disk Adapter below, so the planner itself is
# TTY-free and tests can substitute a non-interactive adapter.
#
# Sourced by lib/layout/zfs/common.sh. Requires: lib/common.sh (part_name) and the
# phase-lifecycle + contract helpers in common.sh, available at call time.
# =============================================================================

# ── Mode-adapter hooks ───────────────────────────────────────────────────────
# The active adapter (single.sh / multi.sh) overrides both. Defaults abort so a
# missing adapter fails loudly rather than planning nothing.

# Mode-specific planning: resolve topology/sizing into the mode-private state and
# publish LAYOUT_OS_POOL_NAME + LAYOUT_DATA_POOL_NAMES. No destructive op, no TTY
# (interactive bits go through the Leftover-Disk Adapter).
_layout_plan_mode() {
  error "layout_plan: no mode adapter sourced (_layout_plan_mode undefined)"
}

# Ordered OS disks that each receive an ESP — primary first. The adapter knows
# its OS-disk set after _layout_plan_mode has run.
_layout_os_disks() {
  error "layout_plan: no mode adapter sourced (_layout_os_disks undefined)"
}

# ── ESP resolution (pure) ────────────────────────────────────────────────────

# Populates LAYOUT_ESP_PARTS from the adapter's ordered OS disks via part_name.
# Pure: a string transform per disk, no block-device access. Primary at index 0.
_layout_resolve_esp_parts() {
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_ESP_PARTS=()
  local d
  while IFS= read -r d; do
    [[ -n "$d" ]] && LAYOUT_ESP_PARTS+=("$(part_name "$d" 1)")
  done < <(_layout_os_disks)
}

# ── Leftover-Disk Adapter (interactive by default; substitutable in tests) ───
# A leftover OS disk (topology=none with 2+ OS disks) is either folded into the
# Combined Data Pool or given its own Standalone Data Pool. The planner asks the
# adapter rather than prompting directly, so it stays pure.
#
#   layout_leftover_choice DISK SIZE     → sets LAYOUT_LEFTOVER_CHOICE=fold|own
#   layout_leftover_pool_name DEF TAKEN… → sets LAYOUT_LEFTOVER_POOL_NAME
#
# Out-params mirror the house PICK_RESULT / POOL_NAME_RESULT style. The default
# adapter wraps the existing pick_option / _prompt_pool_name seams.
# Read by the multi adapter's resolve_leftover_disks (hence SC2034).
# shellcheck disable=SC2034
LAYOUT_LEFTOVER_CHOICE=""
# shellcheck disable=SC2034
LAYOUT_LEFTOVER_POOL_NAME=""

layout_leftover_choice() {
  local disk="$1" size="$2"
  pick_option "Leftover disk ${disk} (${size}):" \
    "fold  (into the Combined Data Pool 'dpool')" \
    "own   (its own Standalone Data Pool, single-disk stripe)"
  # pick_option yields the chosen line's first word (fold|own).
  # shellcheck disable=SC2034
  LAYOUT_LEFTOVER_CHOICE="$(printf '%s' "$PICK_RESULT" | awk '{print $1}')"
}

layout_leftover_pool_name() {
  local def="$1"; shift
  _prompt_pool_name "$def" "$@"
  # shellcheck disable=SC2034
  LAYOUT_LEFTOVER_POOL_NAME="$POOL_NAME_RESULT"
}

# ── The unified plan verb ────────────────────────────────────────────────────

layout_plan() {
  _layout_enter_phase plan
  _layout_plan_mode
  _layout_resolve_esp_parts
  _layout_verify_plan_contract
  _layout_exit_phase plan
}
