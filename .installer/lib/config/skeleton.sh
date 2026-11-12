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

# shellcheck source=../common.sh
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

declare -F json_string_array >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../common.sh"
# shellcheck source=../picker.sh
declare -F _picker_validate_group >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"

# skeleton_preset <name> — the device-less skeleton for a named ZFS shape.
# single   — one disk, no pool skeleton (the picker bakes {mode:single,disk}).
# os-mirror— 2-disk mirrored OS root, no separate storage.
# os-mirror-raidz1 — mirrored OS + a 3-disk raidz1 storage group at /data.
# data-pools— single OS disk (topology none) + a standalone stripe data pool.
skeleton_preset() {
  local os_mirror='os_pool: {pool_name: "rpool", topology: "mirror",'
  os_mirror+=' disk_count: 2}'
  local raidz_data='storage_groups: [{name: "data", mount: "/data",'
  raidz_data+=' topology: "raidz1", disk_count: 3}]'
  local os_none='os_pool: {pool_name: "rpool", topology: "none", disk_count: 1}'
  local tank='data_pools: [{name: "tank", topology: "stripe", disk_count: 1}]'
  local skeleton
  case "$1" in
  single) skeleton='{mode: "single"}' ;;
  os-mirror) skeleton="{mode: \"multi\", ${os_mirror}}" ;;
  os-mirror-raidz1) skeleton="{mode: \"multi\", ${os_mirror}, ${raidz_data}}" ;;
  data-pools) skeleton="{mode: \"multi\", ${os_none}, ${tank}}" ;;
  *)
    error "skeleton_preset: unknown preset '$1'" \
      "(single, os-mirror, os-mirror-raidz1, data-pools)"
    return 1
    ;;
  esac
  # The preset's skeleton.
  jq -n "$skeleton"
}

# ── Composable builders (Advanced authoring) ────────────────────────────────
# The freeform door builds a skeleton group by group rather than from a preset.
# Each returns the new skeleton JSON; skeleton_validate guards the result.

# skeleton_new_multi <os_topology> <os_disk_count> — start a multi skeleton with
# just the OS pool. storage_groups / data_pools are added below.
skeleton_new_multi() {
  local skeleton='{mode: "multi",'
  skeleton+=' os_pool: {pool_name: "rpool", topology: $t, disk_count: $dc}}'
  # A multi skeleton holding only the OS pool.
  jq -n --arg t "$1" --argjson dc "$2" "$skeleton"
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
  local owners_json="[]" group
  local -a owner_list
  if [[ -n "$owners" ]]; then
    read -ra owner_list < <(printf '%s\n' "$owners")
    owners_json="$(json_string_array "${owner_list[@]}")"
  fi
  group='{name: $n, topology: $t, disk_count: $dc}'
  group+=' + (if ($o | length) > 0 then {owners: $o} else {} end)'
  # The group object (owners only when there are some).
  jq -n --arg n "$name" --arg t "$topology" --argjson dc "$disk_count" \
    --argjson o "$owners_json" "$group"
}

# skeleton_add_storage <skeleton> <name> <topology> <disk_count> [owners] —
# append a storage group (mounted at /<name>) to storage_groups[], in order.
skeleton_add_storage() {
  local skeleton="$1"; shift
  local group append
  group="$(_skeleton_group "$@")"
  # The group, mounted at /<name>.
  group="$(printf '%s\n' "$group" | jq --arg m "/$1" '. + {mount: $m}')"
  append='.storage_groups = ((.storage_groups // []) + [$g])'
  # The skeleton with the group appended to storage_groups.
  printf '%s\n' "$skeleton" | jq --argjson g "$group" "$append"
}

# skeleton_add_data_pool <skeleton> <name> <topology> <disk_count> [owners] —
# append a standalone data pool to data_pools[], in order.
skeleton_add_data_pool() {
  local skeleton="$1"; shift
  local pool append
  pool="$(_skeleton_group "$@")"
  append='.data_pools = ((.data_pools // []) + [$p])'
  # The skeleton with the pool appended to data_pools.
  printf '%s\n' "$skeleton" | jq --argjson p "$pool" "$append"
}

# skeleton_total_disks <skeleton> — the flat number of disks the operator must
# pick: Σ disk_count over os_pool + every storage_groups[] + data_pools[].
# single is one disk; os_pool defaults to disk_count 1 when omitted.
skeleton_total_disks() {
  local total='if .mode == "single" then 1 else (.os_pool.disk_count // 1)'
  total+=' + ([.storage_groups[]?.disk_count] | add // 0)'
  total+=' + ([.data_pools[]?.disk_count] | add // 0) end'
  # The number of disks to pick.
  printf '%s\n' "$1" | jq "$total"
}

# _skeleton_read <skeleton> <jq-filter> — one raw value of the skeleton.
_skeleton_read() { printf '%s\n' "$1" | jq -r "$2"; }

# skeleton_validate <skeleton> — rc 0 when every declared group's disk_count
# meets its topology minimum (the shared picker min-disk table), else aborts via
# _picker_validate_group naming the offending group. single is always valid (one
# disk, baked directly). Drives the "installable" guarantee for Advanced (later)
# and guards the presets.
skeleton_validate() {
  local skeleton="$1" topology disk_count count i list
  [[ "$(_skeleton_read "$skeleton" '.mode // "multi"')" == "single" ]] \
    && return 0

  topology="$(_skeleton_read "$skeleton" '.os_pool.topology // "stripe"')"
  disk_count="$(_skeleton_read "$skeleton" '.os_pool.disk_count // 1')"
  _picker_validate_group os_pool "$topology" "$disk_count" || return 1

  for list in storage_groups data_pools; do
    count="$(_skeleton_read "$skeleton" "(.${list} // []) | length")"
    for ((i = 0; i < count; i++)); do
      topology="$(_skeleton_read "$skeleton" \
        ".${list}[$i].topology // \"stripe\"")"
      disk_count="$(_skeleton_read "$skeleton" ".${list}[$i].disk_count // 0")"
      _picker_validate_group "${list}[$i]" "$topology" "$disk_count" \
        || return 1
    done
  done
}

# skeleton_assignment_summary <skeleton> <assignment> — one human line per pool
# group pairing the skeleton's topology/name with the picked disks (the
# assignment shape picker_build_assignment emits: os_pool[], storage_groups[][],
# data_pools[][]). The confirm screen before the install accepts. Pure: lines.
skeleton_assignment_summary() {
  local os storage data
  os='"OS pool (\($s.os_pool.topology // "stripe")): "'
  os+=' + (($a.os_pool // []) | join(", "))'
  storage='($s.storage_groups // []) | to_entries[]'
  storage+=' | "storage \(.value.name) (\(.value.topology)): "'
  storage+=' + ((($a.storage_groups // [])[.key] // []) | join(", "))'
  data='($s.data_pools // []) | to_entries[]'
  data+=' | "data pool \(.value.name) (\(.value.topology)): "'
  data+=' + ((($a.data_pools // [])[.key] // []) | join(", "))'
  # The OS pool line, then a line per storage group and per data pool.
  jq -rn --argjson s "$1" --argjson a "$2" "${os}, (${storage}), (${data})"
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
  local flat flatten
  # One group: its devices[] counted into disk_count, then dropped.
  flat='if has("devices") then (.disk_count = (.devices | length))'
  flat+=' | del(.devices) else . end'
  flatten="(if .os_pool then .os_pool |= (${flat}) else . end)"
  flatten+=" | (if .storage_groups then .storage_groups |= map(${flat})"
  flatten+=' else . end)'
  flatten+=" | (if .data_pools then .data_pools |= map(${flat}) else . end)"
  flatten+=' | del(.root_disk)'
  # The skeleton with every group flattened.
  printf '%s\n' "$1" | jq "$flatten"
}

# skeleton_any_bound <skeleton> — rc 0 when any group carries a devices[] key
# (In-Menu Disk Binding happened), else non-zero (a device-less / counted skel).
skeleton_any_bound() {
  local bound='[.os_pool.devices, ((.storage_groups // [])[].devices),'
  bound+=' ((.data_pools // [])[].devices)] | any(. != null)'
  # Does any group hold devices?
  printf '%s\n' "$1" | jq -e "$bound" >/dev/null 2>&1
}

# skeleton_counted_disks <skeleton> — Σ disk_count over the still-counted
# (device-less) groups only; a bound group contributes nothing (its disks are
# already chosen). Drives how many disks a mixed layout must still flat-pick.
skeleton_counted_disks() {
  local counted='select(has("devices") | not)' sum
  sum="[(.os_pool | select(. != null) | ${counted} | .disk_count // 1),"
  sum+=" ((.storage_groups // [])[] | ${counted} | .disk_count // 0),"
  sum+=" ((.data_pools // [])[] | ${counted} | .disk_count // 0)] | add // 0"
  # The disks the device-less groups still need.
  printf '%s\n' "$1" | jq "$sum"
}

# skeleton_build_assignment <skeleton> <disk...> — the per-group assignment JSON
# (the shape picker_assign_disks consumes). A group with a bound devices[] uses
# it; a device-less group slices disk_count disks from the flat <disk...> list,
# in declared order. Fully bound → call with no disks; fully counted → equals
# picker_build_assignment. Aborts if the disks don't cover the counted groups.
skeleton_build_assignment() {
  local skeleton="$1"; shift
  local -a disks=("$@")
  local offset=0 devices os_json i count list assignment
  local -A lists_json=([storage_groups]="[]" [data_pools]="[]")

  _skeleton_take_devices .os_pool 1
  os_json="$devices"

  for list in storage_groups data_pools; do
    count="$(_skeleton_read "$skeleton" "(.${list} // []) | length")"
    for ((i = 0; i < count; i++)); do
      _skeleton_take_devices ".${list}[$i]" 0
      # The list so far with this group's devices added.
      lists_json[$list]="$(printf '%s\n' "${lists_json[$list]}" \
        | jq --argjson s "$devices" '. + [$s]')"
    done
  done

  (( offset == ${#disks[@]} )) || {
    echo "skeleton_build_assignment: counted groups need $offset disk(s), got" \
         "${#disks[@]}" >&2; return 1; }
  assignment='{mode: "multi", os_pool: $os, storage_groups: $sg,'
  assignment+=' data_pools: $dp}'
  # The assignment object.
  jq -n --argjson os "$os_json" --argjson sg "${lists_json[storage_groups]}" \
    --argjson dp "${lists_json[data_pools]}" "$assignment"
}

# _skeleton_take_devices <group-path> <default-count> — set the caller's
# `devices` to the group's bound devices[], else slice its disk_count from the
# caller's `disks` at `offset`, advancing it. Reads/writes the caller's
# skeleton, disks, offset and devices (dynamic scope).
_skeleton_take_devices() {
  local group_path="$1" default_count="$2" group_disk_count
  # The group's bound devices, compact (nothing when unbound).
  devices="$(printf '%s\n' "$skeleton" \
    | jq -c "${group_path}.devices // empty")"
  [[ -n "$devices" ]] && return 0
  group_disk_count="$(_skeleton_read "$skeleton" \
    "${group_path}.disk_count // ${default_count}")"
  devices="$(_picker_slice_json "${disks[@]:offset:group_disk_count}")"
  offset=$((offset + group_disk_count))
}
