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
#   layout_manual_supported_data_filesystems            → the data filesystems, one per line
#   layout_manual_supported_mounts             → the mountpoints, one per line
#   layout_manual_partition_problems <parts>   → human problems (rc1 if any), NON-fatal
#   layout_manual_partition_validate <parts>   → error()s the FIRST problem + the
#                                         supported-values help (the hard stop)
#   layout_manual_partition_plan <parts>       → validate, then emit the plan
# =============================================================================

# The filesystems the manual Root Layout Adapter can mkfs/mount for a data mount
# (/, /home, …). The ESP is always fat32. Kept in lockstep with root.sh's
# layout_manual_mkfs — the one place both the editor and the back end read.
_MANUAL_DATA_FS=(ext4 xfs btrfs)
# The mountpoints the assignment understands. "" (unassigned) is filtered out.
_MANUAL_MOUNTS=(/ /boot/efi /home "[swap]")

layout_manual_supported_data_filesystems() { printf '%s\n' "${_MANUAL_DATA_FS[@]}"; }
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

# _manual_plan_count <mountpoint> <assigned-json> — how many partitions claim it.
_manual_plan_count() {
  jq --arg m "$1" '[.[] | select(.mountpoint == $m)] | length' <<< "$2"
}

# layout_manual_partition_problems <parts> — every reason the assignment is not yet
# installable, one bullet per line on stdout; rc 1 when there is at least one,
# rc 0 when valid. NON-fatal (no error(), no exit) so the guided menu can show
# it live and the install-time validator can turn it into a hard stop.
layout_manual_partition_problems() {
  local parts="${1:-[]}" assigned count out="" dev mountpoint filesystem esp_filesystem
  assigned="$(jq -c '[.[] | select((.mountpoint // "") != "")]' <<< "$parts")"

  count="$(_manual_plan_count / "$assigned")"
  ((count == 1)) || out+="• ${count} partitions mount at root (/); need one."$'\n'

  count="$(_manual_plan_count /boot/efi "$assigned")"
  if ((count != 1)); then
    out+="• ${count} partitions mount at /boot/efi; need exactly one ESP."$'\n'
  else
    esp_filesystem="$(jq -r '.[] | select(.mountpoint == "/boot/efi") | .fs' \
      <<< "$assigned")"
    [[ "$esp_filesystem" == "fat32" ]] \
      || out+="• the ESP is '${esp_filesystem:-unset}' — it must be fat32."$'\n'
  fi

  # Every assigned partition: a known mountpoint, and a supported fs on a data
  # mount (swap has no fs; the ESP was checked above).
  while IFS=$'\t' read -r dev mountpoint filesystem; do
    [[ -n "$dev" ]] || continue
    if ! printf '%s\n' "${_MANUAL_MOUNTS[@]}" | grep -qxF "$mountpoint"; then
      out+="• ${dev}: mountpoint '${mountpoint}' is not supported."$'\n'
      continue
    fi
    case "$mountpoint" in
    "[swap]" | "/boot/efi") ;;   # swap: no fs; ESP: checked above
    *)
      printf '%s\n' "${_MANUAL_DATA_FS[@]}" | grep -qxF "$filesystem" \
        || out+="• ${dev} (${mountpoint}): fs '${filesystem:-none}' is unsupported."$'\n'
      ;;
    esac
  done < <(jq -r '.[] | [.device, .mountpoint, (.fs // "")] | @tsv' \
    <<< "$assigned")

  [[ -z "$out" ]] && return 0
  printf '%s' "$out"
  return 1
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

# layout_manual_partition_plan <parts> — validate, then emit the plan on stdout:
#   root_device=<dev>
#   esp_device=<dev>
#   mount<TAB><dev><TAB><mountpoint><TAB><fs><TAB><format>   (parents first)
#   swap<TAB><dev>
# Mount records are ordered shallow→deep so a parent (/) mounts before a child
# (/home) and the ESP (/boot/efi) last.
layout_manual_partition_plan() {
  local parts="${1:-[]}"
  layout_manual_partition_validate "$parts"

  local assigned
  assigned="$(jq -c '[.[] | select((.mountpoint // "") != "")]' <<< "$parts")"

  printf 'root_device=%s\n' \
    "$(jq -r '.[] | select(.mountpoint == "/") | .device' <<< "$assigned")"
  printf 'esp_device=%s\n' \
    "$(jq -r '.[] | select(.mountpoint == "/boot/efi") | .device' \
      <<< "$assigned")"

  jq -r '
    [.[] | select(.mountpoint != "[swap]")]
    | sort_by(.mountpoint | split("/") | map(select(. != "")) | length)
    | .[]
    | "mount\t\(.device)\t\(.mountpoint)\t\(.fs)\t\(.format)"
  ' <<< "$assigned"

  jq -r '.[] | select(.mountpoint == "[swap]") | "swap\t\(.device)"' \
    <<< "$assigned"
}
