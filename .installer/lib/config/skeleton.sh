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
#
# Used by: lib/config/profiles.sh, the Guided Installer (lib/guided/),
# vm/lib/flow-guided.sh.
# =============================================================================

# shellcheck source=../picker.sh
declare -F _picker_validate_group >/dev/null 2>&1 \
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

# ── Composable builders (Advanced authoring) ────────────────────────────────
# The freeform door builds a skeleton group by group rather than from a preset.
# Each returns the new skeleton JSON; skeleton_validate guards the result.

# skeleton_new_multi <os_topology> <os_disk_count> — start a multi skeleton with
# just the OS pool. storage_groups / data_pools are added below.
skeleton_new_multi() {
  jq -n --arg t "$1" --argjson dc "$2" \
    '{mode: "multi", os_pool: {pool_name: "rpool", topology: $t, disk_count: $dc}}'
}

# skeleton_custom_seed — the blank-canvas seed the guided `custom…` layout picks
# (ADR 0047): a multi skeleton with a single-disk, topology-none OS pool and no
# storage/data groups, so the unified editor opens ready to author from scratch.
skeleton_custom_seed() { skeleton_new_multi none 1; }

# _skeleton_group <name> <topology> <disk_count> [owners] — one pool group
# object. owners is a whitespace-separated list (a bare token is a user, an
# @-token a group); omitted when empty. ashift is left to the back-end default.
_skeleton_group() {
  local name="$1" topology="$2" disk_count="$3" owners="${4:-}"
  local owners_json="[]"
  # shellcheck disable=SC2086 # owners is a whitespace-separated token list
  [[ -n "$owners" ]] \
    && owners_json="$(printf '%s\n' $owners | jq -R . | jq -s .)"
  jq -n --arg n "$name" --arg t "$topology" --argjson dc "$disk_count" \
    --argjson o "$owners_json" \
    '{name: $n, topology: $t, disk_count: $dc}
     + (if ($o | length) > 0 then {owners: $o} else {} end)'
}

# skeleton_add_storage <skeleton> <name> <topology> <disk_count> [owners] —
# append a storage group (mounted at /<name>) to storage_groups[], in order.
skeleton_add_storage() {
  local skeleton="$1"; shift
  local group; group="$(_skeleton_group "$@")"
  group="$(jq --arg m "/$1" '. + {mount: $m}' <<<"$group")"
  jq --argjson g "$group" '.storage_groups = ((.storage_groups // []) + [$g])' \
    <<<"$skeleton"
}

# skeleton_add_data_pool <skeleton> <name> <topology> <disk_count> [owners] —
# append a standalone data pool to data_pools[], in order.
skeleton_add_data_pool() {
  local skeleton="$1"; shift
  local pool; pool="$(_skeleton_group "$@")"
  jq --argjson p "$pool" '.data_pools = ((.data_pools // []) + [$p])' \
    <<<"$skeleton"
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
  local skeleton="$1" topology disk_count count i
  [[ "$(jq -r '.mode // "multi"' <<<"$skeleton")" == "single" ]] && return 0

  topology="$(jq -r '.os_pool.topology // "stripe"' <<<"$skeleton")"
  disk_count="$(jq -r '.os_pool.disk_count // 1' <<<"$skeleton")"
  _picker_validate_group os_pool "$topology" "$disk_count" || return 1

  count="$(jq '(.storage_groups // []) | length' <<<"$skeleton")"
  for ((i = 0; i < count; i++)); do
    topology="$(jq -r ".storage_groups[$i].topology // \"stripe\"" \
      <<<"$skeleton")"
    disk_count="$(jq -r ".storage_groups[$i].disk_count // 0" <<<"$skeleton")"
    _picker_validate_group "storage_groups[$i]" "$topology" "$disk_count" \
      || return 1
  done

  count="$(jq '(.data_pools // []) | length' <<<"$skeleton")"
  for ((i = 0; i < count; i++)); do
    topology="$(jq -r ".data_pools[$i].topology // \"stripe\"" <<<"$skeleton")"
    disk_count="$(jq -r ".data_pools[$i].disk_count // 0" <<<"$skeleton")"
    _picker_validate_group "data_pools[$i]" "$topology" "$disk_count" \
      || return 1
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

# ── In-Menu Disk Binding: flatten + device-aware assignment (ADR 0047) ───────
# The Guided menu leaves per-group devices[] (and a single-disk root_disk) in
# the in-session skeleton. These lift it into the install assignment or flatten
# it back to a device-less profile — devices[] never reaches a validated form.

# skeleton_flatten_devices <skeleton> — the device-less form: every group's
# disk_count is set to the number of disks bound (when a devices[] is present)
# and the devices[] dropped; the single-disk root_disk is dropped too. Save
# writes this, preserving the device-less profile invariant (ADR 0036).
skeleton_flatten_devices() {
  jq '
    def flat: if has("devices")
              then (.disk_count = (.devices | length)) | del(.devices)
              else . end;
    (if .os_pool then .os_pool |= flat else . end)
    | (if .storage_groups then .storage_groups |= map(flat) else . end)
    | (if .data_pools then .data_pools |= map(flat) else . end)
    | del(.root_disk)
  ' <<<"$1"
}

# skeleton_any_bound <skeleton> — rc 0 when any group carries a devices[] key
# (In-Menu Disk Binding happened), else non-zero (a device-less / counted skel).
skeleton_any_bound() {
  jq -e '[ .os_pool.devices,
           ((.storage_groups // [])[].devices),
           ((.data_pools // [])[].devices) ]
         | any(. != null)' <<<"$1" >/dev/null 2>&1
}

# skeleton_counted_disks <skeleton> — Σ disk_count over the still-counted
# (device-less) groups only; a bound group contributes nothing (its disks are
# already chosen). Drives how many disks a mixed layout must still flat-pick.
skeleton_counted_disks() {
  jq '
    def counted: select(has("devices") | not);
    [ (.os_pool | select(. != null) | counted | .disk_count // 1),
      ((.storage_groups // [])[] | counted | .disk_count // 0),
      ((.data_pools // [])[] | counted | .disk_count // 0) ]
    | add // 0
  ' <<<"$1"
}

# skeleton_build_assignment <skeleton> <disk...> — the per-group assignment JSON
# (the shape picker_assign_disks consumes). A group with a bound devices[] uses
# it; a device-less group slices disk_count disks from the flat <disk...> list,
# in declared order. Fully bound → call with no disks; fully counted → equals
# picker_build_assignment. Aborts if the disks don't cover the counted groups.
skeleton_build_assignment() {
  local skeleton="$1"; shift
  local -a disks=("$@")
  local offset=0 devices os_json i count
  local storage_groups_json="[]" data_pools_json="[]"

  _skeleton_take_devices .os_pool 1
  os_json="$devices"

  count="$(jq '(.storage_groups // []) | length' <<<"$skeleton")"
  for ((i = 0; i < count; i++)); do
    _skeleton_take_devices ".storage_groups[$i]" 0
    storage_groups_json="$(jq --argjson s "$devices" '. + [$s]' \
      <<<"$storage_groups_json")"
  done

  count="$(jq '(.data_pools // []) | length' <<<"$skeleton")"
  for ((i = 0; i < count; i++)); do
    _skeleton_take_devices ".data_pools[$i]" 0
    data_pools_json="$(jq --argjson s "$devices" '. + [$s]' \
      <<<"$data_pools_json")"
  done

  (( offset == ${#disks[@]} )) || {
    echo "skeleton_build_assignment: counted groups need $offset disk(s), got" \
         "${#disks[@]}" >&2; return 1; }
  jq -n --argjson os "$os_json" --argjson sg "$storage_groups_json" \
    --argjson dp "$data_pools_json" \
    '{ mode: "multi", os_pool: $os, storage_groups: $sg, data_pools: $dp }'
}

# _skeleton_take_devices <group-path> <default-count> — set the caller's
# `devices` to the group's bound devices[], else slice its disk_count from the
# caller's `disks` at `offset`, advancing it. Reads/writes the caller's
# skeleton, disks, offset and devices (dynamic scope).
_skeleton_take_devices() {
  local group_path="$1" default_count="$2" group_disk_count
  devices="$(jq -c "${group_path}.devices // empty" <<<"$skeleton")"
  [[ -n "$devices" ]] && return 0
  group_disk_count="$(jq -r "${group_path}.disk_count // ${default_count}" \
    <<<"$skeleton")"
  devices="$(_picker_slice_json "${disks[@]:offset:group_disk_count}")"
  offset=$((offset + group_disk_count))
}
