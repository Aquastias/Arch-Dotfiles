#!/usr/bin/env bash
# =============================================================================
# lib/config/skeleton.sh — Guided Installer Disk Skeleton builder (ADR 0039)
# =============================================================================
# Turns a Disks choice (a named ZFS shape preset; Advanced authoring is a later
# issue) into a *device-less* pool skeleton: mode + os_pool + storage_groups[] /
# data_pools[] carrying topology + disk_count (+ pool/mount names), but NO device
# fields. The skeleton merges into the Config State; the Pre-Install Picker bakes
# devices later (picker_build_assignment slices the picked disks per group's
# disk_count, picker_assign_disks writes them in). The presets' disk_counts
# satisfy the picker min-disk table, so a preset is always installable.
#
# Pure: in-memory JSON on stdout, no TTY. _picker_group_min (picker.sh) is the
# shared min-disk rule, so skeleton_validate and the assignment path never drift.
#
# Public API:
#   skeleton_preset <name>                  → device-less skeleton JSON
#   skeleton_total_disks <skeleton>         → Σ disk_count (disks to collect)
#   skeleton_validate <skeleton>            → rc 0 if every group meets its
#                                             topology min, else names the group
#   skeleton_assignment_summary <skel> <a>  → per-group confirm lines
# =============================================================================

# shellcheck source=../picker.sh
[[ "$(type -t _picker_validate_group)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"

# skeleton_preset <name> — the device-less skeleton for a named ZFS shape.
# single   — one disk, no pool skeleton (the picker bakes {mode:single,disk}).
# os-mirror— 2-disk mirrored OS root, no separate storage.
# os-mirror-raidz1 — mirrored OS + a 3-disk raidz1 storage group at /data.
# data-pools— single OS disk (topology none) + a standalone stripe data pool.
skeleton_preset() {
  case "$1" in
  single)
    jq -n '{mode: "single"}'
    ;;
  os-mirror)
    jq -n '{mode: "multi",
            os_pool: {pool_name: "rpool", topology: "mirror", disk_count: 2}}'
    ;;
  os-mirror-raidz1)
    jq -n '{mode: "multi",
            os_pool: {pool_name: "rpool", topology: "mirror", disk_count: 2},
            storage_groups: [{name: "data", mount: "/data",
                              topology: "raidz1", disk_count: 3}]}'
    ;;
  data-pools)
    jq -n '{mode: "multi",
            os_pool: {pool_name: "rpool", topology: "none", disk_count: 1},
            data_pools: [{name: "tank", topology: "stripe", disk_count: 1}]}'
    ;;
  *)
    error "skeleton_preset: unknown preset '$1'" \
      "(single, os-mirror, os-mirror-raidz1, data-pools)"
    ;;
  esac
}

# skeleton_total_disks <skeleton> — the flat number of disks the operator must
# pick: Σ disk_count over os_pool + every storage_groups[] + data_pools[].
# single is one disk; os_pool defaults to disk_count 1 when omitted.
skeleton_total_disks() {
  jq '
    if .mode == "single" then 1
    else
      (.os_pool.disk_count // 1)
      + ([.storage_groups[]?.disk_count] | add // 0)
      + ([.data_pools[]?.disk_count] | add // 0)
    end
  ' <<<"$1"
}

# skeleton_validate <skeleton> — rc 0 when every declared group's disk_count
# meets its topology minimum (the shared picker min-disk table), else aborts via
# _picker_validate_group naming the offending group. single is always valid (one
# disk, baked directly). Drives the "installable" guarantee for Advanced (later)
# and guards the presets.
skeleton_validate() {
  local skel="$1" topo dc n i
  [[ "$(jq -r '.mode // "multi"' <<<"$skel")" == "single" ]] && return 0

  topo="$(jq -r '.os_pool.topology // "stripe"' <<<"$skel")"
  dc="$(jq -r '.os_pool.disk_count // 1' <<<"$skel")"
  _picker_validate_group os_pool "$topo" "$dc" || return 1

  n="$(jq '(.storage_groups // []) | length' <<<"$skel")"
  for ((i = 0; i < n; i++)); do
    topo="$(jq -r ".storage_groups[$i].topology // \"stripe\"" <<<"$skel")"
    dc="$(jq -r ".storage_groups[$i].disk_count // 0" <<<"$skel")"
    _picker_validate_group "storage_groups[$i]" "$topo" "$dc" || return 1
  done

  n="$(jq '(.data_pools // []) | length' <<<"$skel")"
  for ((i = 0; i < n; i++)); do
    topo="$(jq -r ".data_pools[$i].topology // \"stripe\"" <<<"$skel")"
    dc="$(jq -r ".data_pools[$i].disk_count // 0" <<<"$skel")"
    _picker_validate_group "data_pools[$i]" "$topo" "$dc" || return 1
  done
}

# skeleton_assignment_summary <skeleton> <assignment> — one human line per pool
# group pairing the skeleton's topology/name with the picked disks (the
# assignment shape picker_build_assignment emits: os_pool[], storage_groups[][],
# data_pools[][]). The confirm screen before the install accepts. Pure: lines.
skeleton_assignment_summary() {
  jq -rn --argjson s "$1" --argjson a "$2" '
    [ "OS pool (\($s.os_pool.topology // "stripe")): "
      + (($a.os_pool // []) | join(", ")) ]
    + [ ($s.storage_groups // []) | to_entries[]
        | "storage \(.value.name) (\(.value.topology)): "
          + ((($a.storage_groups // [])[.key] // []) | join(", ")) ]
    + [ ($s.data_pools // []) | to_entries[]
        | "data pool \(.value.name) (\(.value.topology)): "
          + ((($a.data_pools // [])[.key] // []) | join(", ")) ]
    | .[]
  '
}
