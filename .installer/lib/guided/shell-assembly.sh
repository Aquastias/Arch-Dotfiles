#!/usr/bin/env bash
# =============================================================================
# lib/guided/shell-assembly.sh — Guided shell session state + identity/disk
# edits
# =============================================================================
# Part of the Guided Installer fzf shell (lib/guided/shell.sh, ADR 0039).
#
# Used by: lib/guided/shell.sh (sources it).
# =============================================================================

# =============================================================================
# ASSEMBLY
# =============================================================================
# In-flight session state for one guided run. Two layers (issue 01):
#   _GUIDED_BASELINE — seeded launch defaults, set once, held constant (not
#     snapshotted, not an override).
#   _GUIDED_STATE — the operator's sparse OVERRIDE map (empty at launch); every
#     edit writes here, so the ● flag reflects operator intent only.
# Effective config = BASELINE * STATE, read via _guided_shell_effective.
_GUIDED_BASELINE=""
_GUIDED_STATE=""
_GUIDED_DISK=""
# Terminal action (issue 08): "proceed" | "save" | "export" — set by the menu
# loop (interactive) or the `terminal` replay key. Save/Export return
# _GUIDED_ACTION_DONE so install.sh skips the back-end (the action is terminal).
_GUIDED_ACTION=""
readonly _GUIDED_ACTION_DONE=64
# The Undo/Redo snapshot stack over the Config State (issue 02). Its present is
# kept in lockstep with _GUIDED_STATE: every interactive mutation commits, and
# undo/redo restore _GUIDED_STATE from the stack — so leaving and re-entering,
# or stepping back and forth, never loses a value.
_GUIDED_HIST=""

# _guided_shell_set_identity — seed launch defaults into the BASELINE layer
# (hostname, Primary User, single-disk layout, locale/timezone/keymap). A
# default, not an override, so a fresh run carries no ● yet still emits
# (validation.sh requires locale + timezone, and the host must never be
# userless).
_guided_shell_set_identity() {
  _GUIDED_BASELINE="$(config_state_seed_defaults "$(config_state_new)")"
}

# _guided_shell_effective — the effective override map the back-end consumes:
# the operator's overrides merged over the seeded baseline (jq `*`, so an
# override REPLACES a baseline array/scalar — letting the operator drop a seeded
# user — and deep-merges objects). Emit, Save and the seeded-value reads use
# this.
_guided_shell_effective() {
  jq -n --argjson b "${_GUIDED_BASELINE:-{\}}" \
    --argjson o "${_GUIDED_STATE:-{\}}" '$b * $o'
}

# _guided_shell_edit_hostname — read the hostname (seam key 'hostname') and
# commit it.
_guided_shell_edit_hostname() {
  local value
  value="$(guided_prompt hostname "Hostname")"
  _GUIDED_STATE="$(edit_set_scalar "$_GUIDED_STATE" system.hostname "$value")"
}

# _guided_shell_edit_locale / _guided_shell_edit_timezone /
# _guided_shell_edit_keymap — the three editable Host identity rows over the
# seeded defaults. Each is a free-text scalar through the seam (empty input
# no-ops, keeping the seed). _guided_edit_ scalar lives in the Options block
# below; these reuse it for the Host section.
_guided_shell_edit_locale() {
  _guided_shell_edit_scalar locale "Locale (e.g. en_US.UTF-8)" system.locale
}
_guided_shell_edit_timezone() {
  _guided_shell_edit_scalar timezone "Timezone (e.g. Europe/Bucharest)" \
    system.timezone
}
_guided_shell_edit_keymap() {
  _guided_shell_edit_scalar keymap "Keymap (e.g. us)" system.keymap
}

# _guided_shell_edit_disk — resolve the single install disk (Disks ▸ ZFS ▸
# single).
_guided_shell_edit_disk() { _GUIDED_DISK="$(guided_pick_disk disk)"; }

# _guided_shell_edit_manual — replay-only Manual Partitioning (ADR 0073): the
# `manual_disk` answer names a disk whose table was drawn beforehand (the VM
# case scripts it in place of the operator's cfdisk). Switches the disk kind to
# manual and stores the scanned assignment; that disk is also the install disk.
_guided_shell_edit_manual() {
  local disk="${_GUIDED_ANSWERS[manual_disk]-}"
  [[ -n "$disk" ]] || return 1
  _GUIDED_STATE="$(edit_set_scalar "$_GUIDED_STATE" disk_config.kind manual)"
  _GUIDED_STATE="$(manual_partition_scan_and_store "$_GUIDED_STATE" "$disk")" \
    || return 1
  _GUIDED_DISK="$disk"
}

# Disk layout presets (issue 04): the named ZFS shapes the operator picks before
# disks are resolved. single keeps the one-disk path; the rest author a
# device-less pool skeleton (skeleton_preset) merged into the Config State, then
# baked at Proceed by collecting Σ disk_count disks.
_GUIDED_LAYOUTS=(single os-mirror os-mirror-raidz1 data-pools advanced)

# _guided_shell_apply_skeleton <skeleton> — drop any previous skeleton keys,
# then merge the new one into the Config State (switching layouts never leaves a
# stale group behind).
_guided_shell_apply_skeleton() {
  _GUIDED_STATE="$(edit_apply_skeleton "$_GUIDED_STATE" "$1")"
}

# _guided_shell_edit_layout — pick a disk-layout preset (or Advanced authoring)
# and merge the resulting skeleton into the Config State. rc 1 (no change) when
# the pick is empty (e.g. an absent replay answer keeps the default single
# path).
_guided_shell_edit_layout() {
  local pick skeleton
  pick="$(guided_select layout "Disk layout" "${_GUIDED_LAYOUTS[@]}")"
  [[ -n "$pick" ]] || return 1
  [[ "$pick" == "advanced" ]] && { _guided_shell_author_skeleton; return; }
  skeleton="$(skeleton_preset "$pick")" || return 1
  _guided_shell_apply_skeleton "$skeleton"
}

# _guided_shell_author_skeleton — the Advanced door: author an arbitrary pool
# skeleton group by group (OS pool, then N storage groups, then N data pools),
# each via the seam so a replay file (and the interactive menu) drive the same
# builders. skeleton_validate gates the result against the min-disk table before
# it is applied. rc 1 (no change) on a cancelled pick or an un-installable
# skeleton.
_guided_shell_author_skeleton() {
  local os_topology os_disk_count skeleton
  os_topology="$(guided_select adv_os_topology "OS pool topology" \
    mirror stripe raidz1 raidz2 none)"
  [[ -n "$os_topology" ]] || return 1
  os_disk_count="$(guided_prompt adv_os_disk_count "OS pool disk count")"
  [[ -n "$os_disk_count" ]] || return 1
  skeleton="$(skeleton_new_multi "$os_topology" "$os_disk_count")"

  _guided_shell_author_groups adv_storage "Number of storage groups" storage \
    skeleton_add_storage mirror stripe raidz1 raidz2
  _guided_shell_author_groups adv_data "Number of data pools" data \
    skeleton_add_data_pool stripe mirror raidz1 raidz2

  skeleton_validate "$skeleton" || return 1
  _guided_shell_apply_skeleton "$skeleton"
}

# _guided_shell_author_groups <answer-prefix> <count-prompt> <label> <adder>
# <topology…> — prompt for each group (name, topology, disk count, owners) and
# append it to the caller's `skeleton` with <adder> (dynamic scope).
_guided_shell_author_groups() {
  local prefix="$1" count_prompt="$2" label="$3" adder="$4"
  shift 4
  local count i name topology disk_count owners
  count="$(guided_prompt "${prefix}_count" "$count_prompt")"
  for ((i = 0; i < ${count:-0}; i++)); do
    name="$(guided_prompt "${prefix}_${i}_name" "${label}[$i] name")"
    topology="$(guided_select "${prefix}_${i}_topology" \
      "${label}[$i] topology" "$@")"
    disk_count="$(guided_prompt "${prefix}_${i}_disk_count" \
      "${label}[$i] disk count")"
    owners="$(guided_prompt "${prefix}_${i}_owners" "${label}[$i] owners")"
    skeleton="$("$adder" "$skeleton" "$name" "$topology" "$disk_count" \
      "$owners")"
  done
}

# _guided_shell_inject_devices <kind> <index> <space-list> — set the group's
# devices[] to the by-id list (word-split) and derive its disk_count, mirroring
# the in-menu bind (ADR 0047). kind is os_pool (singleton) | storage | data.
# Mutates _GUIDED_STATE. Shared by the headless replay device-binding form.
_guided_shell_inject_devices() {
  local kind="$1" index="$2" list="$3" devices_json
  # shellcheck disable=SC2086 # the list is a whitespace-separated by-id set
  devices_json="$(printf '%s\n' $list | jq -R . \
    | jq -s -c 'map(select(length > 0))')"
  case "$kind" in
  os_pool) _GUIDED_STATE="$(jq -c --argjson d "$devices_json" \
    '.os_pool.devices = $d | .os_pool.disk_count = ($d | length)' \
    <<<"$_GUIDED_STATE")" ;;
  storage) _GUIDED_STATE="$(jq -c --argjson i "$index" \
    --argjson d "$devices_json" \
    '.storage_groups[$i].devices = $d
     | .storage_groups[$i].disk_count = ($d | length)' \
    <<<"$_GUIDED_STATE")" ;;
  data)    _GUIDED_STATE="$(jq -c --argjson i "$index" \
    --argjson d "$devices_json" \
    '.data_pools[$i].devices = $d
     | .data_pools[$i].disk_count = ($d | length)' \
    <<<"$_GUIDED_STATE")" ;;
  esac
}

# _guided_shell_edit_bound_devices — the headless-replay In-Menu Disk Binding
# form (ADR 0047). In-menu binding is interactive-only; this lets a `--guided`
# answers file inject each pool's bound disks so the bound assignment path
# (issue 04) runs without a tty. Answer keys: os_pool_devices,
# storage_<N>_devices, data_<N>_devices — each a whitespace-separated
# /dev/disk/by-id/* list. A group with no key stays device-less (falls back to
# the counted flat pick). No-op when not replaying (the persistent menu binds
# disks itself).
_guided_shell_edit_bound_devices() {
  ((_GUIDED_REPLAY)) || return 0
  [[ -n "${_GUIDED_ANSWERS[os_pool_devices]-}" ]] \
    && _guided_shell_inject_devices os_pool 0 \
      "${_GUIDED_ANSWERS[os_pool_devices]}"
  local key
  for key in "${!_GUIDED_ANSWERS[@]}"; do
    if [[ "$key" =~ ^storage_([0-9]+)_devices$ ]]; then
      _guided_shell_inject_devices storage "${BASH_REMATCH[1]}" \
        "${_GUIDED_ANSWERS[$key]}"
    elif [[ "$key" =~ ^data_([0-9]+)_devices$ ]]; then
      _guided_shell_inject_devices data "${BASH_REMATCH[1]}" \
        "${_GUIDED_ANSWERS[$key]}"
    fi
  done
}

# guided_pick_disks <key> <n> — resolve <n> install disks (multi-disk layouts).
# Replay: the scripted answer is a whitespace-separated device list.
# Interactive:
# an fzf multi-select over the picker candidates. Emits one device per line.
guided_pick_disks() {
  local key="$1" count="$2" live
  if ((_GUIDED_REPLAY)); then
    # shellcheck disable=SC2086 # the answer is a whitespace-separated disk list
    printf '%s\n' ${_GUIDED_ANSWERS[$key]-}
    return
  fi
  live="$(live_medium_disks)"
  local -a candidates
  mapfile -t candidates < <(picker_enum_disks "$live")
  ((${#candidates[@]} >= count)) \
    || { error "guided: need $count disks, only ${#candidates[@]} found"
         return 1; }
  # Readable labels (field 1) over the by-id paths (hidden field 2); emit the
  # picked paths, one per line.
  local path
  for path in "${candidates[@]}"; do
    printf '%s\t%s\n' "$(picker_disk_label "$path")" "$path"
  done | fzf --reverse --multi --prompt="pick ${count} disks (TAB to mark)> " \
    --delimiter='\t' --with-nth=1 \
    | while IFS=$'\t' read -r _label path; do printf '%s\n' "$path"; done
}

# Filesystem Adapter axis (ADR 0040/0043): the Root Layout Adapters that are
# BUILT (issue 09). All four now ship (zfs/btrfs/ext4/xfs); _GUIDED_FS_RESERVED
# stays as the seam for any future adapter that lands unbuilt. Kept in lockstep
# with lib/layout/dispatch.sh's root_adapter_source (the source of truth).
_GUIDED_FS_ACTIVE=(zfs btrfs ext4 xfs)
_GUIDED_FS_RESERVED=()

# _guided_shell_filesystem_options — the filesystem picker lines: active
# filesystems first, then the reserved ones flagged "(reserved)". Pure: emits
# lines.
_guided_shell_filesystem_options() {
  printf '%s\n' "${_GUIDED_FS_ACTIVE[@]}"
  local filesystem
  for filesystem in "${_GUIDED_FS_RESERVED[@]}"; do
    printf '%s (reserved)\n' "$filesystem"
  done
}

# _guided_shell_edit_filesystem — pick the filesystem; commit only an active
# one. A reserved pick is refused (rc 1, no commit) so the loop never offers an
# unbuilt adapter. The token is the first word of the picked line.
_guided_shell_edit_filesystem() {
  local -a options
  mapfile -t options < <(_guided_shell_filesystem_options)
  local pick token filesystem
  pick="$(guided_select filesystem "Filesystem" "${options[@]}")"
  [[ -n "$pick" ]] || return 0
  token="${pick%% *}"
  for filesystem in "${_GUIDED_FS_ACTIVE[@]}"; do
    if [[ "$token" == "$filesystem" ]]; then
      _GUIDED_STATE="$(config_state_set "$_GUIDED_STATE" filesystem \
        "$(jq -n --arg x "$token" '$x')")"
      return 0
    fi
  done
  printf "  Filesystem '%s' is reserved (ADR 0040); its adapter is not \
built.\n" "$token" >&2
  return 1
}

# _guided_shell_edit_bool <key> <prompt> <path> — a true/false toggle through
# the seam (replay-friendly: the answer is the literal "true"/"false"). Sets
# <path> to the JSON bool. rc 1 (no commit) when the pick is neither — e.g. an
# absent replay answer — so a no-op edit never snapshots.
_guided_shell_edit_bool() {
  local key="$1" prompt="$2" path="$3" value
  value="$(guided_select "$key" "$prompt" true false)"
  _GUIDED_STATE="$(edit_set_bool "$_GUIDED_STATE" "$path" "$value")"
}

# _guided_shell_edit_encryption / _guided_shell_edit_impermanence — the two
# Disks bools. Encryption enablement is the bool; the cipher is the
# filesystem-derived encryption_method (ADR 0040). Impermanence-on lets the
# back-end apply the Curated Persist Defaults and surfaces the persist-extension
# action below.
_guided_shell_edit_encryption() {
  _guided_shell_edit_bool encryption "Encryption (true/false)" \
    options.encryption
}
_guided_shell_edit_impermanence() {
  _guided_shell_edit_bool impermanence "Impermanence (true/false)" \
    options.impermanence.enabled
}

# _guided_shell_add_persist — append one operator-typed absolute directory to
# persist.directories (a Persist Extension over the Curated Persist Defaults).
# rc 1 (no commit) on empty input.
_guided_shell_add_persist() {
  local directory
  directory="$(guided_prompt persist_dir "Persist directory (absolute path)")"
  _GUIDED_STATE="$(edit_append_persist "$_GUIDED_STATE" "$directory")"
}
