#!/usr/bin/env bash
# =============================================================================
# lib/layout/manual/plan.sh — Manual Partitioning planner/validator (ADR 0073)
# =============================================================================
# The pure core under the manual Root Layout Adapter. Takes the operator's
# partitions[] assignment — a JSON array of {device, mountpoint, fs, format} the
# Guided Installer built from a cfdisk session — and emits a validated
# format+mount plan the adapter executes, or aborts via error() naming the
# offending condition. Partitions with no mountpoint are ignored (left on the
# disk, untouched). Pure: parses its JSON argument only, no disk access.
#
# Public API:
#   manual_partition_plan <partitions-json>
#     Validates: exactly one root (/), exactly one FAT32 ESP (/boot/efi).
#     Emits on stdout:
#       root_device=<dev>
#       esp_device=<dev>
#       mount<TAB><dev><TAB><mountpoint><TAB><fs><TAB><format>   (parents first)
#       swap<TAB><dev>
#     The mount records are ordered shallow→deep by mountpoint so a parent
#     (/) always mounts before a child (/home), and the ESP (/boot/efi) last.
#
# Uses error() from common.sh (available at call time).
# =============================================================================

manual_partition_plan() {
  local parts="${1:-[]}"

  # Assigned = only entries the operator gave a mountpoint. The rest stay on
  # the disk, neither formatted nor mounted.
  local assigned
  assigned="$(jq -c '[.[] | select((.mountpoint // "") != "")]' <<< "$parts")"

  # Root: exactly one partition mounted at "/".
  local root_n
  root_n="$(jq '[.[] | select(.mountpoint == "/")] | length' <<< "$assigned")"
  if ((root_n == 0)); then
    error "Manual layout: no partition is mounted at root (/)." \
      "Assign one partition the '/' mountpoint."
  elif ((root_n > 1)); then
    error "Manual layout: ${root_n} partitions claim root (/);" \
      "exactly one is allowed."
  fi

  # ESP: exactly one partition mounted at "/boot/efi", and it must be FAT32.
  local esp_n
  esp_n="$(jq '[.[] | select(.mountpoint == "/boot/efi")] | length' \
    <<< "$assigned")"
  if ((esp_n == 0)); then
    error "Manual layout: no EFI System Partition mounted at /boot/efi." \
      "Assign a FAT32 partition the '/boot/efi' mountpoint."
  elif ((esp_n > 1)); then
    error "Manual layout: ${esp_n} partitions claim /boot/efi;" \
      "exactly one is allowed."
  fi
  local esp_fs
  esp_fs="$(jq -r '.[] | select(.mountpoint == "/boot/efi") | .fs' \
    <<< "$assigned")"
  if [[ "$esp_fs" != "fat32" ]]; then
    error "Manual layout: the ESP (/boot/efi) must be FAT32," \
      "not '${esp_fs:-unset}'."
  fi

  # Summary devices the adapter/boot record key off.
  printf 'root_device=%s\n' \
    "$(jq -r '.[] | select(.mountpoint == "/") | .device' <<< "$assigned")"
  printf 'esp_device=%s\n' \
    "$(jq -r '.[] | select(.mountpoint == "/boot/efi") | .device' \
      <<< "$assigned")"

  # Filesystem mounts, ordered shallow→deep (parents before children) by the
  # count of non-empty path segments: "/"=0, "/home"=1, "/boot/efi"=2.
  jq -r '
    [.[] | select(.mountpoint != "[swap]")]
    | sort_by(.mountpoint | split("/") | map(select(. != "")) | length)
    | .[]
    | "mount\t\(.device)\t\(.mountpoint)\t\(.fs)\t\(.format)"
  ' <<< "$assigned"

  # Swap partitions (operator-cut, type 8200), activated but never mounted.
  jq -r '.[] | select(.mountpoint == "[swap]") | "swap\t\(.device)"' \
    <<< "$assigned"
}
