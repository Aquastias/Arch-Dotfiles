#!/usr/bin/env bash
# =============================================================================
# lib/layout/core.sh — filesystem-agnostic Layout Module core (ADR 0043)
# =============================================================================
# The shared spine every Root Layout Adapter builds on: the phase lifecycle,
# size parsers, ESP-size helpers, ESP resolution, the unified `layout_plan`
# verb, and the contract verifiers. Filesystem-specific behaviour is supplied
# by the adapter overriding the seam hooks below (`_layout_plan_mode`,
# `_layout_os_disks`, `_layout_publish_boot`) and, for ZFS, an extended
# `_layout_verify_plan_contract`.
#
# Sourced by lib/layout/zfs/common.sh and lib/layout/nonzfs/root.sh.
# Requires: lib/common.sh already sourced (provides config_optional, error, part_name).
# =============================================================================

# The root-fs-agnostic Standalone Data Pool orchestrator — every root adapter's
# seam verbs call resolve/partition/layout_create_data_pools from here (ADR 0027/0043).
# shellcheck source=./data-pools.sh
declare -F layout_create_data_pools >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/data-pools.sh"

# ESP budget model — kernel-aware sizing + the pre-install guard (ADR 0078).
# shellcheck source=../boot/esp-budget.sh
declare -F esp_budget_auto_size >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../boot/esp-budget.sh"

# ── ESP size (config) ────────────────────────────────────────────────────────

# Number of selected kernels — the driver of the ESP budget.
_core_kernel_count() { install_config_kernels | grep -c .; }

# Reads .options.esp_size. The default `auto` is resolved to a kernel-and-fs
# aware size (upward-only from the 2G floor) via
# the ESP budget model (ADR 0078); an explicit numeric pin is returned as-is.
layout_resolve_esp_size() {
  local raw; raw="$(install_config_esp_size)"
  [[ "$raw" == auto ]] || { printf '%s\n' "$raw"; return 0; }
  esp_budget_auto_size "$(_core_kernel_count)" \
    "$(install_config_filesystem)" "$(install_config_bootloader)"
}

# Fail-fast guard: the resolved ESP size must meet the 1 GiB floor (ADR 0038)
# AND, for an explicit pin on an ESP-mirroring loader, hold every selected
# kernel's images (ADR 0078). `auto` is sufficient by construction, so only a
# pin can fail. Errors name the field, the shortfall, and the `auto` escape.
layout_validate_esp_size() {
  local raw size mib
  raw="$(install_config_esp_size)"
  size="$(layout_resolve_esp_size)"
  mib="$(layout_parse_size_to_mib "$size")"
  ((mib >= 1024)) || error \
    "esp_size '${size}' is below the 1G floor for a resilient boot path" \
    "(ADR 0038). Set options.esp_size to at least 1G (default 2G)."

  [[ "$raw" == auto ]] && return 0
  local kernel_count filesystem bootloader need
  kernel_count="$(_core_kernel_count)"
  filesystem="$(install_config_filesystem)"
  bootloader="$(install_config_bootloader)"
  esp_budget_fits_mib "$mib" "$kernel_count" "$filesystem" "$bootloader" && return 0
  need="$(esp_budget_auto_size "$kernel_count" "$filesystem" "$bootloader")"
  error "esp_size '${size}' is too small for ${kernel_count} kernel(s) on ${bootloader}" \
    "(ADR 0078). Use at least ${need}, or set options.esp_size to auto."
}

# layout_disk_exists <path> — 0 iff <path> is a present block device. The single
# seam behind every adapter's disk-existence probe (single/multi/nonzfs/btrfs),
# so the check is overridable in unit tests that use fake disk paths and by the
# no-VM Tier-1 assembly oracle (Combination Matrix, ADR 0046), which runs
# validation_check_install_context without real disks. Production behaviour is
# `-b`.
layout_disk_exists() { [[ -b "$1" ]]; }

# layout_settle — after sgdisk + partprobe, wait for udev to create the
# partition nodes and /dev/disk/by-id/*-partN links mkfs and zpool open; a
# bare sleep raced it on slow controllers.
layout_settle() {
  udevadm settle --timeout=30 2>/dev/null || true
  sleep 2
}

# ── Size parsers ─────────────────────────────────────────────────────────────

# Converts a size string ("512M", "80G", "2T") to integer GiB, rounded up.
layout_parse_size_to_gib() {
  local raw="${1^^}"
  local number="${raw//[^0-9]/}"
  local unit="${raw//[0-9]/}"
  # Base 10 explicitly: a leading zero (010G) must not read as octal.
  [[ -n "$number" ]] || error "Cannot parse size string: '$1'"
  number=$((10#$number))
  case "$unit" in
  M | MIB) echo $(((number + 1023) / 1024)) ;;
  G | GIB) echo "$number" ;;
  T | TIB) echo $((number * 1024)) ;;
  *) error "Cannot parse size string: '$1'" ;;
  esac
}

# Converts a size string ("512M", "2G", "1T") to integer MiB with no rounding
# loss. Unlike layout_parse_size_to_gib, this keeps sub-GiB precision so the ESP floor
# can distinguish 512M from 1G.
layout_parse_size_to_mib() {
  local raw="${1^^}"
  local number="${raw//[^0-9]/}"
  local unit="${raw//[0-9]/}"
  # Base 10 explicitly: a leading zero (010G) must not read as octal.
  [[ -n "$number" ]] || error "Cannot parse size string: '$1'"
  number=$((10#$number))
  case "$unit" in
  M | MIB) echo "$number" ;;
  G | GIB) echo $((number * 1024)) ;;
  T | TIB) echo $((number * 1024 * 1024)) ;;
  *) error "Cannot parse size string: '$1'" ;;
  esac
}

# ── Plan text protocol (shared) ──────────────────────────────────────────────

# Read one field out of a `key=value` plan text on stdin (the non-ZFS root
# partition plan, the device plan, and the per-group datacrypt plan all share
# this line format). The single reader for all three — root.sh, devices.sh, and
# data.sh used to each carry a byte-identical copy. Exits 1 when the key is
# absent (as the grep it replaced did), so a missing field still fails.
layout_plan_field() {
  awk -v key="$1" '
    index($0, key "=") == 1 { print substr($0, length(key) + 2); found = 1 }
    END { exit !found }
  '
}

# ── Plan / partition contract (ESP — shared) ─────────────────────────────────

# Asserts layout_plan() resolved at least one ESP partition (ESP paths are
# decided at plan time, ADR 0034). The default plan contract; the ZFS adapter
# overrides this to also require LAYOUT_OS_POOL_NAME. Call at end of layout_plan().
_layout_verify_plan_contract() {
  ((${#LAYOUT_ESP_PARTS[@]} >= 1)) ||
    error "Layout contract: LAYOUT_ESP_PARTS must have ≥1 element" \
          "after layout_plan()"
}

# Asserts layout_partition() populated LAYOUT_ESP_PARTS.
# Call at end of every layout_partition().
layout_verify_partition_contract() {
  ((${#LAYOUT_ESP_PARTS[@]} >= 1)) ||
    error "Layout contract: LAYOUT_ESP_PARTS must have ≥1 element" \
          "after layout_partition()"
}

# =============================================================================
# Layout phase lifecycle (ADR 0016)
# =============================================================================
# Single ordinal counter + two guards enforce seam-verb ordering. Adapters
# bracket each verb with layout_enter_phase / layout_exit_phase. Out-of-order
# calls abort via error before any destructive operation runs.
#
# Phase map (private): validate=1, plan=2, partition=3, pools=4, esp=5.
# Seeded to 0 — the first callable phase is `validate` (ADR 0014).
_LAYOUT_PHASE=0

_core_phase_ordinal() {
  case "$1" in
  validate)  echo 1 ;;
  plan)      echo 2 ;;
  partition) echo 3 ;;
  pools)     echo 4 ;;
  esp)       echo 5 ;;
  *) error "Unknown layout phase name: '$1'" ;;
  esac
}

layout_enter_phase() {
  local name="$1" ord
  ord="$(_core_phase_ordinal "$name")"
  (( _LAYOUT_PHASE == ord - 1 )) ||
    error "Layout phase '$name' out of order:" \
          "_LAYOUT_PHASE=$_LAYOUT_PHASE, expected $((ord - 1))"
}

layout_exit_phase() {
  local name="$1" ord
  ord="$(_core_phase_ordinal "$name")"
  _LAYOUT_PHASE="$ord"
}

# =============================================================================
# The unified plan verb + seam hooks (ADR 0034/0043)
# =============================================================================
# The active adapter overrides each hook. Defaults abort so a missing adapter
# fails loudly rather than planning nothing.

# Mode-specific planning: resolve topology/sizing into adapter-private state and
# publish the LAYOUT_* record. No destructive op, no TTY.
_layout_plan_mode() {
  error "layout_plan: no adapter sourced (_layout_plan_mode undefined)"
}

# Ordered OS disks that each receive an ESP — primary first.
_layout_os_disks() {
  error "layout_plan: no adapter sourced (_layout_os_disks undefined)"
}

# Publishes the filesystem-blind boot record (LAYOUT_ROOT_CMDLINE / LAYOUT_HOOKS,
# ADR 0043). The adapter that can resolve both at plan time sets both here; an
# adapter whose root cmdline depends on a post-format UUID sets LAYOUT_HOOKS here
# and LAYOUT_ROOT_CMDLINE in its format verb (both are read later, at
# install_state_write time).
_layout_publish_boot() {
  error "layout_plan: no adapter sourced (_layout_publish_boot undefined)"
}

# Populates LAYOUT_ESP_PARTS from the adapter's ordered OS disks via part_name.
# Pure: a string transform per disk, no block-device access. Primary at index 0.
_core_resolve_esp_parts() {
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_ESP_PARTS=()
  local disk
  while IFS= read -r disk; do
    [[ -n "$disk" ]] && LAYOUT_ESP_PARTS+=("$(part_name "$disk" 1)")
  done < <(_layout_os_disks)
}

# The unified plan verb: bracket the plan phase, dispatch to the adapter's
# planning hook, resolve the ESP partitions, publish the boot record, verify the
# contract. Destructive verbs (partition / create / mount) stay in the adapter.
layout_plan() {
  layout_enter_phase plan
  _layout_plan_mode
  _core_resolve_esp_parts
  _layout_publish_boot
  _layout_verify_plan_contract
  layout_exit_phase plan
}
