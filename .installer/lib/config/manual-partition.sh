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
#   manual_scan_partitions <lsblk-json>   → seeded partitions[] (JSON array)
#   manual_set_field <parts> <dev> <k> <v> → partitions[] with one field changed
#   manual_kind_active <state>            → 0 when disk_config.kind is manual
# =============================================================================

# shellcheck source=./state.sh
declare -F cfgstate_get >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/state.sh"
# The supported-filesystem / mountpoint source of truth + the validator live in
# the back-end planner; the editor and its live problem notice read from there.
# shellcheck source=../layout/manual/plan.sh
declare -F manual_partition_problems >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../layout/manual/plan.sh"

_MANUAL_ESP_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"   # EFI System Partition
_MANUAL_SWAP_GUID="0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"  # Linux swap

# manual_scan_partitions <lsblk-json> — seed the assignment from a disk's
# partition table. Input is `lsblk -J -b -o` with the PATH,TYPE,FSTYPE,PARTTYPE,
# PARTTYPENAME columns (JSON). Every partition becomes an entry; the ESP (EFI or
# vfat) pre-fills /boot/efi + fat32 and swap (swap type/fs) pre-fills [swap], so
# the obvious cases need no operator action. A partition with no existing
# filesystem defaults to format=true (there is nothing to keep); one that
# already carries data defaults to keep. Everything else starts unassigned.
manual_scan_partitions() {
  local lsblk="$1"
  jq -c \
    --arg esp "$_MANUAL_ESP_GUID" \
    --arg swap "$_MANUAL_SWAP_GUID" '
    [ .blockdevices | .. | objects | select(.type? == "part") ]
    | map(
        ((.parttype // "") | ascii_downcase) as $pt
      | ((.parttypename // "") | ascii_downcase) as $pn
      | (.fstype // "") as $fst
      | (($pt == $esp) or ($pn | test("efi")) or ($fst == "vfat")) as $is_esp
      | (($pt == $swap) or ($pn | test("swap")) or ($fst == "swap")) as $is_swap
      | { device: .path,
          size: (.size // 0),
          mountpoint: (if $is_esp then "/boot/efi"
                       elif $is_swap then "[swap]" else "" end),
          fs:     (if $is_esp then "fat32"
                   elif $fst != "" then $fst else "" end),
          format: ($fst == "") }
      )' <<< "$lsblk"
}

# manual_autoassign_root <partitions-json> — if nothing is mounted at "/", give
# it to the largest still-unassigned, non-ESP/non-swap partition (root is almost
# always the big one), defaulting its filesystem to ext4 when blank. Idempotent:
# a table that already names a root is returned unchanged. This lets a plain
# `ESP + root [+ swap]` cfdisk layout install with no further assignment; richer
# layouts (kept /home, dual-boot) are edited partition-by-partition. Pure.
manual_autoassign_root() {
  jq -c '
    if any(.[]; .mountpoint == "/") then .
    else
      ( [ to_entries[] | select(.value.mountpoint == "") ]
        | sort_by(.value.size) | last ) as $pick
      | if $pick == null then .
        else .[$pick.key].mountpoint = "/"
             | (if (.[$pick.key].fs // "") == "" then .[$pick.key].fs = "ext4"
                else . end)
             | .[$pick.key].format = true
        end
    end' <<< "$1"
}

# manual_target_disk — the disk cfdisk runs on: the first enumerable install
# candidate minus the live medium (GUIDED_LIVE_SET), resolved to its kernel
# node. rc 1 when none found. (A multi-disk target picker is a refinement.)
manual_target_disk() {
  local first
  first="$(picker_enum_disks "${GUIDED_LIVE_SET:-}" 2>/dev/null | head -n1)"
  [[ -n "$first" ]] || return 1
  readlink -f "$first"
}

# manual_set_field <partitions-json> <device> <field> <value> — set one field
# (mountpoint | fs | format) on the entry for <device>. `format` is coerced to a
# JSON boolean; the rest are strings. Unknown devices pass through unchanged.
manual_set_field() {
  local parts="$1" dev="$2" field="$3" val="$4"
  local jval
  if [[ "$field" == "format" ]]; then
    [[ "$val" == "true" ]] && jval=true || jval=false
  else
    jval="$(jq -n --arg v "$val" '$v')"
  fi
  jq -c --arg d "$dev" --arg f "$field" --argjson v "$jval" \
    'map(if .device == $d then .[$f] = $v else . end)' <<< "$parts"
}

# The mountpoint cycle for the assignment sub-screen: Enter on a partition
# advances it through these, wrapping. "" = unassigned (left on the disk).
_MANUAL_MOUNTPOINTS=("" "/" "/boot/efi" "/home" "[swap]")

# manual_cycle_mountpoint <current> — the next mountpoint after <current> in the
# cycle (wrapping); the first entry when <current> is unknown. Pure.
manual_cycle_mountpoint() {
  local cur="$1" i n=${#_MANUAL_MOUNTPOINTS[@]}
  for i in "${!_MANUAL_MOUNTPOINTS[@]}"; do
    [[ "${_MANUAL_MOUNTPOINTS[$i]}" == "$cur" ]] \
      && { printf '%s' "${_MANUAL_MOUNTPOINTS[$(((i + 1) % n))]}"; return; }
  done
  printf '%s' "${_MANUAL_MOUNTPOINTS[0]}"
}

# manual_cycle_fs <current> — the next data filesystem after <current> in the
# supported cycle (ext4 → xfs → btrfs, wrapping); the first when <current> is
# unknown. Only the filesystems the installer can build are offered, so the
# editor can never author an unsupported one (manual_supported_data_fs is the
# source of truth, from the planner). Pure.
manual_cycle_fs() {
  local cur="$1" first="" found="" f
  while IFS= read -r f; do
    [[ -z "$first" ]] && first="$f"
    [[ -n "$found" ]] && { printf '%s' "$f"; return; }
    [[ "$f" == "$cur" ]] && found=1
  done < <(manual_supported_data_fs)
  printf '%s' "$first"
}

# manual_row_label <partition-json> — the one-line assignment row for a
# partition: "<device>  →  <mountpoint or '(unassigned)'>  <fs>  [keep|format]".
# Pure: reads the object only.
manual_row_label() {
  jq -r '
    (.mountpoint // "") as $m
    | "\(.device)  →  \(if $m == "" then "(unassigned)" else $m end)"
      + (if (.fs // "") != "" then "  \(.fs)" else "" end)
      + (if .format then "  [format]" else "  [keep]" end)' <<< "$1"
}

# manual_store_partitions <state> <partitions-json> — write the assignment into
# Config State under disk_config.partitions (transient; ADR 0036 keeps it out of
# any committed/exported artifact). The one place the assignment enters state.
manual_store_partitions() {
  cfgstate_set "$1" disk_config.partitions "$2"
}

# manual_kind_active <state> — 0 when Manual Partitioning is the active disk
# kind. The guided terminal-action gate uses it to withhold Save Profile and
# Export (a hand-drawn table is Proceed-only — ADR 0073).
manual_kind_active() {
  [[ "$(cfgstate_get "$1" disk_config.kind)" == "manual" ]]
}

# manual_lsblk_json <disk> — the partition table of <disk> as the JSON
# manual_scan_partitions expects. The one impure read, isolated so the seed
# stays pure and testable. Overridable via MANUAL_LSBLK_CMD for the VM harness.
manual_lsblk_json() {
  ${MANUAL_LSBLK_CMD:-lsblk} -J -b \
    -o PATH,TYPE,SIZE,FSTYPE,PARTTYPE,PARTTYPENAME "$1"
}

# manual_partition_flow <state> <disk> — the interactive hand-off: launch cfdisk
# on <disk> so the operator draws the table, then re-read it, seed the
# assignment, and store it into Config State (via manual_store_partitions).
# Emits the new state on stdout. The cfdisk + lsblk steps are the only
# TTY/disk-touching part; the seed and store are the pure model above, and the
# per-partition edits are then driven by the fzf sub-screen through
# manual_set_field. VM-verified end to end (the manual matrix case).
manual_partition_flow() {
  local state="$1" disk="$2" parts
  cfdisk "$disk"
  parts="$(manual_scan_partitions "$(manual_lsblk_json "$disk")")"
  parts="$(manual_autoassign_root "$parts")"
  manual_store_partitions "$state" "$parts"
}
