#!/usr/bin/env bash
# =============================================================================
# lib/config/manual-partition.sh — Manual Partitioning assignment model (0073)
# =============================================================================
# The pure core behind the Guided Installer's cfdisk hand-off. After the
# operator partitions a disk by hand, this seeds the assignment table from the
# resulting partition list and edits it — turning `lsblk` output into the
# disk_config.partitions[] the manual Root Layout Adapter consumes. The disk
# picking (fzf), the cfdisk launch, and the re-read are the thin interactive
# shell (manual_partition_flow, VM-verified in the matrix case); everything that
# decides *what an assignment means* lives here so it is testable headless.
#
# Pure (the seed/edit functions): JSON in, JSON out, no disk access. The GPT
# type GUIDs are the stable identity for the ESP / swap pre-fill.
#
# Public API:
#   manual_partition_scan <lsblk-json>   → seeded partitions[] (JSON array)
#   manual_partition_set_field <partitions> <device> <field> <value>
#       → partitions[] with one field changed
#   manual_partition_kind_active <state> → 0 when disk_config.kind is manual
#
# Used by: lib/guided/controller.sh, lib/guided/shell.sh.
# =============================================================================

# shellcheck source=./config-state.sh
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

declare -F config_state_get >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config-state.sh"
# The supported-filesystem / mountpoint source of truth + the validator live in
# the back-end planner; the editor and its live problem notice read from there.
# shellcheck source=../layout/manual/plan.sh
declare -F layout_manual_partition_problems >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../layout/manual/plan.sh"

_MANUAL_ESP_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"   # EFI System Partition
_MANUAL_SWAP_GUID="0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"  # Linux swap

# manual_partition_scan <lsblk-json> — seed the assignment from a disk's
# partition table. Input is `lsblk -J -b -o` with the PATH,TYPE,FSTYPE,PARTTYPE,
# PARTTYPENAME columns (JSON). Every partition becomes an entry; the ESP (EFI or
# vfat) pre-fills /boot/efi + fat32 and swap (swap type/fs) pre-fills [swap], so
# the obvious cases need no operator action. A partition with no existing
# filesystem defaults to format=true (there is nothing to keep); one that
# already carries data defaults to keep. Everything else starts unassigned.
manual_partition_scan() {
  local lsblk="$1"
  # The assignment table (manual-partition-scan.jq).
  printf '%s\n' "$lsblk" | jq -c \
    --arg esp "$_MANUAL_ESP_GUID" \
    --arg swap "$_MANUAL_SWAP_GUID" \
    -f "${BASH_SOURCE[0]%/*}/manual-partition-scan.jq"
}

# manual_partition_autoassign_root <partitions-json> — if nothing is mounted at
# "/", give it to the largest still-unassigned, non-ESP/non-swap partition (root
# is almost always the big one), defaulting its filesystem to ext4 when blank.
# Idempotent: a table that already names a root is returned unchanged. This lets
# a plain `ESP + root [+ swap]` cfdisk layout install with no further
# assignment; richer layouts (kept /home, dual-boot) are edited
# partition-by-partition. Pure.
manual_partition_autoassign_root() {
  # The table with a root assigned (manual-partition-autoassign.jq).
  printf '%s\n' "$1" \
    | jq -c -f "${BASH_SOURCE[0]%/*}/manual-partition-autoassign.jq"
}

# manual_partition_target_disk — the disk cfdisk runs on (ADR 0073): the
# operator's pick among the install candidates minus the live medium
# (GUIDED_LIVE_SET), resolved to its kernel node; a lone candidate is used
# without asking. rc 1 when none is found or the pick is cancelled.
manual_partition_target_disk() {
  local -a candidates
  local chosen
  mapfile -t candidates \
    < <(picker_enum_disks "${GUIDED_LIVE_SET:-}" 2>/dev/null)
  ((${#candidates[@]})) || return 1
  if ((${#candidates[@]} == 1)); then
    chosen="${candidates[0]}"
  else
    chosen="$(_manual_partition_choose_disk "${candidates[@]}")" || return 1
  fi
  [[ -n "$chosen" ]] || return 1
  readlink -f "$chosen"
}

# _manual_partition_choose_disk <by-id>... — fzf pick, labelled like the main
# disk picker (runs under fzf execute(), so it has the tty).
_manual_partition_choose_disk() {
  local path pick
  pick="$(for path in "$@"; do
      printf '%s\t%s\n' "$(picker_disk_label "$path")" "$path"
    done | fzf --reverse --prompt='cfdisk on> ' --delimiter='\t' \
      --with-nth=1)" || return 1
  # The by-id path after the label.
  printf '%s\n' "$pick" | cut -f2-
}

# manual_partition_set_field <partitions-json> <device> <field> <value> — set
# one field (mountpoint | fs | format) on the entry for <device>. `format` is
# coerced to a JSON boolean; the rest are strings. Unknown devices pass through
# unchanged.
manual_partition_set_field() {
  local partitions="$1" device="$2" field="$3" value="$4"
  local json_value set='map(if .device == $d then .[$f] = $v else . end)'
  if [[ "$field" == "format" ]]; then
    [[ "$value" == "true" ]] && json_value=true || json_value=false
  else
    # The value as a JSON string.
    json_value="$(jq -n --arg v "$value" '$v')"
  fi
  # The table with that device's field set.
  printf '%s\n' "$partitions" \
    | jq -c --arg d "$device" --arg f "$field" --argjson v "$json_value" "$set"
}

# The mountpoint cycle for the assignment sub-screen: Enter on a partition
# advances it through these, wrapping. "" = unassigned (left on the disk).
_MANUAL_MOUNTPOINTS=("" "/" "/boot/efi" "/home" "[swap]")

# manual_partition_cycle_mountpoint <current> — the next mountpoint after
# <current> in the cycle (wrapping); the first entry when <current> is unknown.
# Pure.
manual_partition_cycle_mountpoint() {
  local current="$1" i count=${#_MANUAL_MOUNTPOINTS[@]}
  for i in "${!_MANUAL_MOUNTPOINTS[@]}"; do
    [[ "${_MANUAL_MOUNTPOINTS[$i]}" == "$current" ]] \
      && { printf '%s' "${_MANUAL_MOUNTPOINTS[$(((i + 1) % count))]}"; return; }
  done
  printf '%s' "${_MANUAL_MOUNTPOINTS[0]}"
}

# manual_partition_cycle_filesystem <current> — the next data filesystem after
# <current> in the supported cycle (ext4 → xfs → btrfs, wrapping); the first
# when <current> is unknown. Only the filesystems the installer can build are
# offered, so the editor can never author an unsupported one
# (layout_manual_supported_data_filesystems is the source of truth, from the
# planner). Pure.
manual_partition_cycle_filesystem() {
  local current="$1" first="" found="" filesystem
  while IFS= read -r filesystem; do
    [[ -z "$first" ]] && first="$filesystem"
    [[ -n "$found" ]] && { printf '%s' "$filesystem"; return; }
    [[ "$filesystem" == "$current" ]] && found=1
  done < <(layout_manual_supported_data_filesystems)
  printf '%s' "$first"
}

# manual_partition_row_label <partition-json> — the one-line assignment row for
# a partition: "<device> → <mountpoint or '(unassigned)'> <fs> [keep|format]".
# Pure: reads the object only.
manual_partition_row_label() {
  local label='(.mountpoint // "") as $m'
  label+=' | "\(.device)  →  \(if $m == "" then "(unassigned)" else $m end)"'
  label+=' + (if (.fs // "") != "" then "  \(.fs)" else "" end)'
  label+=' + (if .format then "  [format]" else "  [keep]" end)'
  # The partition's row.
  printf '%s\n' "$1" | jq -r "$label"
}

# manual_partition_store <state> <partitions-json> — write the assignment into
# Config State under disk_config.partitions (transient; ADR 0036 keeps it out of
# any committed/exported artifact). The one place the assignment enters state.
manual_partition_store() {
  config_state_set "$1" disk_config.partitions "$2"
}

# manual_partition_kind_active <state> — 0 when Manual Partitioning is the
# active disk kind. The guided terminal-action gate uses it to withhold Save
# Profile and Export (a hand-drawn table is Proceed-only — ADR 0073).
manual_partition_kind_active() {
  [[ "$(config_state_get "$1" disk_config.kind)" == "manual" ]]
}

# manual_partition_lsblk_json <disk> — the partition table of <disk> as the JSON
# manual_partition_scan expects. The one impure read, isolated so the seed
# stays pure and testable. Overridable via MANUAL_LSBLK_CMD for the VM harness.
manual_partition_lsblk_json() {
  ${MANUAL_LSBLK_CMD:-lsblk} -J -b \
    -o PATH,TYPE,SIZE,FSTYPE,PARTTYPE,PARTTYPENAME "$1"
}

# manual_partition_flow <state> <disk> — the interactive hand-off: launch cfdisk
# on <disk> so the operator draws the table, then re-read it, seed the
# assignment, and store it into Config State (via manual_partition_store).
# Emits the new state on stdout. The cfdisk + lsblk steps are the only
# TTY/disk-touching part; the seed and store are the pure model above, and the
# per-partition edits are then driven by the fzf sub-screen through
# manual_partition_set_field. VM-verified end to end (the manual matrix case).
manual_partition_flow() {
  cfdisk "$2"
  manual_partition_scan_and_store "$1" "$2"
}

# manual_partition_scan_and_store <state> <disk> — read <disk>'s existing table,
# seed the assignment and store it (the cfdisk-free half of the flow). The
# headless replay drives this directly on a scripted table (the VM manual case).
manual_partition_scan_and_store() {
  local parts
  parts="$(manual_partition_scan "$(manual_partition_lsblk_json "$2")")"
  parts="$(manual_partition_autoassign_root "$parts")"
  manual_partition_store "$1" "$parts"
}
