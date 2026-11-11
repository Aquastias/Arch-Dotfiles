#!/usr/bin/env bash
# =============================================================================
# lib/layout/manual/plan.sh — Manual Partitioning planner/validator (ADR 0073)
# =============================================================================
# The pure core under the manual Root Layout Adapter. Takes the operator's
# partitions[] assignment — a JSON array of {device, mountpoint, fs, format} the
# Guided Installer built from a cfdisk session — validates it against what the
# installer can actually build, and emits a format+mount plan the adapter
# executes. Partitions with no mountpoint are ignored (left on the disk).
#
# The set of filesystems and mountpoints the installer supports is declared ONCE
# here and shared by the validator, the install-time hard stop, and the guided
# assignment editor's cycles — so the menu can only ever offer, and the back end
# only ever accept, the same values.
#
# Pure: parses its JSON argument only, no disk access. Uses error() (common.sh).
#
# Public API:
#   layout_manual_supported_data_filesystems → the data filesystems, one per
#                                              line
#   layout_manual_supported_mounts           → the mountpoints, one per line
#   layout_manual_partition_problems <parts> → human problems (rc1 if any),
#                                              NON-fatal
#   layout_manual_partition_validate <parts> → error()s the FIRST problem +
#                                              the supported-values help (the
#                                              hard stop)
#   layout_manual_partition_plan <parts>     → validate, then emit the plan
# =============================================================================

# The filesystems the manual Root Layout Adapter can mkfs/mount for a data mount
# (/, /home, …). The ESP is always fat32. Kept in lockstep with root.sh's
# layout_manual_mkfs — the one place both the editor and the back end read.
_MANUAL_DATA_FS=(ext4 xfs btrfs)
# The mountpoints the assignment understands. "" (unassigned) is filtered out.
_MANUAL_MOUNTS=(/ /boot/efi /home "[swap]")

layout_manual_supported_data_filesystems() {
  printf '%s\n' "${_MANUAL_DATA_FS[@]}"
}
layout_manual_supported_mounts()  { printf '%s\n' "${_MANUAL_MOUNTS[@]}"; }

# The "here is what the installer supports — change cfdisk / the assignment to
# match" help appended to every hard stop, so the operator knows exactly how to
# make the layout installable.
layout_manual_supported_help() {
  cat <<EOF
The installer can only create and mount these filesystems:
  ext4, xfs, btrfs  — for data mounts (/, /home)
  fat32             — for the EFI System Partition (/boot/efi)
Supported mountpoints: / , /boot/efi , /home , [swap].
Re-run cfdisk (or change the assignment) so every partition uses a supported
filesystem and mountpoint, then try again.
EOF
}

# The jq step listing the assigned partitions (those with a mountpoint), one
# "device|mountpoint|fs|format" row each; a missing fs or format reads "null".
# shellcheck disable=SC2016 # a jq program, not shell
_MANUAL_PLAN_ROW_PROGRAM='.[] | select((.mountpoint // "") != "")
  | "\(.device)|\(.mountpoint)|\(.fs)|\(.format)"'

# _manual_plan_rows <parts> — the assigned partitions, one row each.
_manual_plan_rows() {
  # One "device|mountpoint|fs|format" row per assigned partition.
  printf '%s\n' "${1:-[]}" | jq -r "$_MANUAL_PLAN_ROW_PROGRAM"
}

# _manual_plan_is_listed <word> <list>… — 0 when <word> is in <list>.
_manual_plan_is_listed() {
  local word="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$word" ]] && return 0
  done
  return 1
}

# layout_manual_partition_problems <parts> — every reason the assignment is
# not yet installable, one bullet per line on stdout; rc 1 when there is at
# least one, rc 0 when valid. NON-fatal (no error(), no exit) so the guided
# menu can show it live and the install-time validator can turn it into a
# hard stop.
layout_manual_partition_problems() {
  local out="" row device mountpoint filesystem _format problem
  local root_count=0 esp_count=0 esp_filesystem=""
  local -a rows
  mapfile -t rows < <(_manual_plan_rows "${1:-[]}")
  for row in "${rows[@]}"; do
    IFS='|' read -r device mountpoint filesystem _format \
      < <(printf '%s\n' "$row")
    [[ "$mountpoint" == / ]] && root_count=$((root_count + 1))
    if [[ "$mountpoint" == /boot/efi ]]; then
      esp_count=$((esp_count + 1))
      esp_filesystem="$filesystem"
    fi
  done

  ((root_count == 1)) \
    || out+="• ${root_count} partitions mount at root (/); need one."$'\n'
  if ((esp_count != 1)); then
    out+="• ${esp_count} partitions mount at /boot/efi;"
    out+=" need exactly one ESP."$'\n'
  elif [[ "$esp_filesystem" != "fat32" ]]; then
    out+="• the ESP is '${esp_filesystem:-unset}' — it must be fat32."$'\n'
  fi

  # Every assigned partition: a known mountpoint, and a supported fs on a data
  # mount (swap has no fs; the ESP was checked above).
  for row in "${rows[@]}"; do
    IFS='|' read -r device mountpoint filesystem _format \
      < <(printf '%s\n' "$row")
    [[ -n "$device" ]] || continue
    [[ "$filesystem" == null ]] && filesystem=""
    problem="$(_manual_plan_partition_problem "$device" "$mountpoint" \
      "$filesystem")"
    [[ -n "$problem" ]] && out+="$problem"$'\n'
  done

  [[ -z "$out" ]] && return 0
  printf '%s' "$out"
  return 1
}

# _manual_plan_partition_problem <device> <mountpoint> <fs> — the problem
# bullet for one partition, or nothing when it is fine.
_manual_plan_partition_problem() {
  local device="$1" mountpoint="$2" filesystem="$3"
  if ! _manual_plan_is_listed "$mountpoint" "${_MANUAL_MOUNTS[@]}"; then
    printf '%s' "• ${device}: mountpoint '${mountpoint}' is not supported."
    return 0
  fi
  case "$mountpoint" in
  "[swap]" | "/boot/efi") ;;   # swap: no fs; ESP: checked above
  *)
    _manual_plan_is_listed "$filesystem" "${_MANUAL_DATA_FS[@]}" \
      || printf '%s' \
        "• ${device} (${mountpoint}): fs '${filesystem:-none}' is unsupported."
    ;;
  esac
  return 0
}

# layout_manual_partition_validate <parts> — the install-time hard stop: if the
# assignment has any problem, abort via error() with the first problem AND the
# supported-values help, so an out-of-bounds cfdisk layout stops the install
# before any disk write and tells the operator exactly what to change.
layout_manual_partition_validate() {
  local probs
  probs="$(layout_manual_partition_problems "${1:-[]}")" && return 0
  error "Manual layout is not installable:"$'\n'"${probs}"$'\n' \
    "$(layout_manual_supported_help)"
}

# _manual_plan_depth <mountpoint> — how many path parts it has: / → 0,
# /home → 1, /boot/efi → 2.
_manual_plan_depth() {
  local path_part depth=0
  local -a path_parts
  IFS=/ read -ra path_parts < <(printf '%s\n' "$1")
  for path_part in "${path_parts[@]}"; do
    [[ -n "$path_part" ]] && depth=$((depth + 1))
  done
  printf '%s\n' "$depth"
}

# layout_manual_partition_plan <parts> — validate, then emit the plan on stdout:
#   root_device=<dev>
#   esp_device=<dev>
#   mount<TAB><dev><TAB><mountpoint><TAB><fs><TAB><format>   (parents first)
#   swap<TAB><dev>
# Mount records are ordered shallow→deep so a parent (/) mounts before a child
# (/home) and the ESP (/boot/efi) last.
layout_manual_partition_plan() {
  local parts="${1:-[]}" row device mountpoint filesystem format record
  local -a rows mounts=() swaps=()
  local root_device="" esp_device=""
  layout_manual_partition_validate "$parts"
  mapfile -t rows < <(_manual_plan_rows "$parts")
  for row in "${rows[@]}"; do
    IFS='|' read -r device mountpoint filesystem format \
      < <(printf '%s\n' "$row")
    [[ "$mountpoint" == / ]] && root_device="$device"
    [[ "$mountpoint" == /boot/efi ]] && esp_device="$device"
    if [[ "$mountpoint" == "[swap]" ]]; then
      swaps+=("swap"$'\t'"$device")
    else
      # The depth first, so a stable numeric sort puts parents first.
      record="$(printf 'mount\t%s\t%s\t%s\t%s' "$device" "$mountpoint" \
        "$filesystem" "$format")"
      mounts+=("$(_manual_plan_depth "$mountpoint")|$record")
    fi
  done
  printf 'root_device=%s\n' "$root_device"
  printf 'esp_device=%s\n' "$esp_device"
  if (( ${#mounts[@]} )); then
    # The mount records shallow → deep, without their depth prefix.
    printf '%s\n' "${mounts[@]}" | sort -s -t'|' -k1,1n | cut -d'|' -f2-
  fi
  if (( ${#swaps[@]} )); then printf '%s\n' "${swaps[@]}"; fi
}
