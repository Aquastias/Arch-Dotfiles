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
#   manual_supported_data_fs            → the data filesystems, one per line
#   manual_supported_mounts             → the mountpoints, one per line
#   manual_partition_problems <parts>   → human problems (rc1 if any), NON-fatal
#   manual_partition_validate <parts>   → error()s the FIRST problem + the
#                                         supported-values help (the hard stop)
#   manual_partition_plan <parts>       → validate, then emit the plan
# =============================================================================

# The filesystems the manual Root Layout Adapter can mkfs/mount for a data mount
# (/, /home, …). The ESP is always fat32. Kept in lockstep with root.sh's
# _manual_mkfs — the one place both the editor and the back end read.
_MANUAL_DATA_FS=(ext4 xfs btrfs)
# The mountpoints the assignment understands. "" (unassigned) is filtered out.
_MANUAL_MOUNTS=(/ /boot/efi /home "[swap]")

manual_supported_data_fs() { printf '%s\n' "${_MANUAL_DATA_FS[@]}"; }
manual_supported_mounts()  { printf '%s\n' "${_MANUAL_MOUNTS[@]}"; }

# The "here is what the installer supports — change cfdisk / the assignment to
# match" help appended to every hard stop, so the operator knows exactly how to
# make the layout installable.
manual_supported_help() {
  cat <<EOF
The installer can only create and mount these filesystems:
  ext4, xfs, btrfs  — for data mounts (/, /home)
  fat32             — for the EFI System Partition (/boot/efi)
Supported mountpoints: / , /boot/efi , /home , [swap].
Re-run cfdisk (or change the assignment) so every partition uses a supported
filesystem and mountpoint, then try again.
EOF
}

# _manual_count <mountpoint> <assigned-json> — how many partitions claim it.
_manual_count() {
  jq --arg m "$1" '[.[] | select(.mountpoint == $m)] | length' <<< "$2"
}

# manual_partition_problems <parts> — every reason the assignment is not yet
# installable, one bullet per line on stdout; rc 1 when there is at least one,
# rc 0 when valid. NON-fatal (no error(), no exit) so the guided menu can show
# it live and the install-time validator can turn it into a hard stop.
manual_partition_problems() {
  local parts="${1:-[]}" assigned n out="" dev mnt fs esp_fs
  assigned="$(jq -c '[.[] | select((.mountpoint // "") != "")]' <<< "$parts")"

  n="$(_manual_count / "$assigned")"
  ((n == 1)) || out+="• ${n} partitions mount at root (/); need one."$'\n'

  n="$(_manual_count /boot/efi "$assigned")"
  if ((n != 1)); then
    out+="• ${n} partitions mount at /boot/efi; need exactly one ESP."$'\n'
  else
    esp_fs="$(jq -r '.[] | select(.mountpoint == "/boot/efi") | .fs' \
      <<< "$assigned")"
    [[ "$esp_fs" == "fat32" ]] \
      || out+="• the ESP is '${esp_fs:-unset}' — it must be fat32."$'\n'
  fi

  # Every assigned partition: a known mountpoint, and a supported fs on a data
  # mount (swap has no fs; the ESP was checked above).
  while IFS=$'\t' read -r dev mnt fs; do
    [[ -n "$dev" ]] || continue
    if ! printf '%s\n' "${_MANUAL_MOUNTS[@]}" | grep -qxF "$mnt"; then
      out+="• ${dev}: mountpoint '${mnt}' is not supported."$'\n'
      continue
    fi
    case "$mnt" in
    "[swap]" | "/boot/efi") ;;   # swap: no fs; ESP: checked above
    *)
      printf '%s\n' "${_MANUAL_DATA_FS[@]}" | grep -qxF "$fs" \
        || out+="• ${dev} (${mnt}): fs '${fs:-none}' is unsupported."$'\n'
      ;;
    esac
  done < <(jq -r '.[] | [.device, .mountpoint, (.fs // "")] | @tsv' \
    <<< "$assigned")

  [[ -z "$out" ]] && return 0
  printf '%s' "$out"
  return 1
}

# manual_partition_validate <parts> — the install-time hard stop: if the
# assignment has any problem, abort via error() with the first problem AND the
# supported-values help, so an out-of-bounds cfdisk layout stops the install
# before any disk write and tells the operator exactly what to change.
manual_partition_validate() {
  local probs
  probs="$(manual_partition_problems "${1:-[]}")" && return 0
  error "Manual layout is not installable:"$'\n'"${probs}"$'\n' \
    "$(manual_supported_help)"
}

# manual_partition_plan <parts> — validate, then emit the plan on stdout:
#   root_device=<dev>
#   esp_device=<dev>
#   mount<TAB><dev><TAB><mountpoint><TAB><fs><TAB><format>   (parents first)
#   swap<TAB><dev>
# Mount records are ordered shallow→deep so a parent (/) mounts before a child
# (/home) and the ESP (/boot/efi) last.
manual_partition_plan() {
  local parts="${1:-[]}"
  manual_partition_validate "$parts"

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
