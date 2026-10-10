#!/usr/bin/env bash
# =============================================================================
# lib/wipe/selection.sh — which disks the wipe may touch
# =============================================================================
# Detects eligible disks (never the live medium, never a disk with a mounted
# partition), prints the disk table, and turns the operator's include-based
# answer into DISKS_TO_WIPE.
#
# Used by: 02-wipe.sh. Requires lib/common.sh and lib/live-medium.sh.
# main()-free, so sourcing is inert.
# =============================================================================

# wipe_detect_disks — eligible whole-disk paths, one per line. Diagnostics go to
# stderr: stdout is captured verbatim as the disk list, so a stray line there
# would be taken as a disk to wipe. The live medium is excluded via the
# Live-Medium Detector (lib/live-medium.sh), matched by whole-disk path.
wipe_detect_disks() {
  local live_set
  live_set="$(live_medium_disks)"
  [[ -n "$live_set" ]] \
    && info "Live medium detected (excluded): $(join_words <<<"$live_set")" >&2

  local disks=() kernel_name path
  while IFS= read -r kernel_name; do
    path="/dev/${kernel_name}"
    grep -qxF "$path" <<<"$live_set" && continue
    if _selection_has_mounted_partition "$path"; then
      warn "Skipping $path — has mounted partitions." >&2
      continue
    fi
    disks+=("$path")
  done < <(lsblk -dno NAME,TYPE,RO | awk '$2=="disk" && $3=="0" {print $1}')

  ((${#disks[@]} > 0)) && printf '%s\n' "${disks[@]}" || true
}

# _selection_has_mounted_partition <disk> — 0 if any of its partitions is
# mounted.
_selection_has_mounted_partition() {
  local partition
  while IFS= read -r partition; do
    grep -q "^/dev/${partition}" /proc/mounts 2>/dev/null && return 0
  done < <(lsblk -ln -o NAME "$1" 2>/dev/null | awk 'NR > 1')
  return 1
}

# _selection_disk_type <disk> — NVMe, SSD, HDD or ?.
_selection_disk_type() {
  local rotational transport
  rotational="$(lsblk -dno ROTA "$1" 2>/dev/null || echo '?')"
  transport="$(lsblk -dno TRAN "$1" 2>/dev/null | join_words || echo '?')"
  if [[ "$transport" == "nvme" ]]; then echo "NVMe"
  elif [[ "$rotational" == "0" ]]; then echo "SSD"
  elif [[ "$rotational" == "1" ]]; then echo "HDD"
  else echo "?"; fi
}

wipe_print_disk_table() {
  local disks=("$@")
  # SC2059: BOLD/NC colour escapes are interpolated into the format.
  # shellcheck disable=SC2059
  printf "\n  ${BOLD}%-5s  %-14s  %-8s  %-8s  %-28s  %s${NC}\n" \
    "Idx" "Device" "Size" "Type" "Model" "Serial"
  printf "  %s\n" "$(printf '─%.0s' {1..84})"
  local index=1 disk size model serial
  for disk in "${disks[@]}"; do
    size="$(lsblk -dno SIZE "$disk" 2>/dev/null | join_words || echo '?')"
    model="$(lsblk -dno MODEL "$disk" 2>/dev/null | join_words \
      || echo 'unknown')"
    serial="$(lsblk -dno SERIAL "$disk" 2>/dev/null | join_words || echo '-')"
    # shellcheck disable=SC2059  # see header printf above
    printf "  ${BOLD}%-5s${NC}  %-14s  %-8s  %-8s  %-28s  %s\n" \
      "[$index]" "$disk" "$size" "$(_selection_disk_type "$disk")" \
      "${model:0:28}" "$serial"
    ((index++))
  done
  echo ""
}

# wipe_parse_selection INPUT DISK... — pure include-based selection, one path
# per line. Empty INPUT selects nothing (default-cancel).
wipe_parse_selection() {
  local input="$1"; shift
  [[ -z "${input//[[:space:]]/}" ]] && return 0  # cancel → wipe nothing
  if [[ "${input,,}" == "all" ]]; then
    printf '%s\n' "$@"
    return 0
  fi
  # 1-based indices. Non-numeric / out-of-range tokens are skipped (never wipe a
  # disk you didn't name); a repeated index is emitted once (first-seen order).
  local all=("$@") token picked=()
  local -A seen=()
  for token in $input; do
    [[ "$token" =~ ^[0-9]+$ ]] || continue
    (( token >= 1 && token <= ${#all[@]} )) || continue
    [[ -n "${seen[$token]:-}" ]] && continue
    seen[$token]=1
    picked+=("${all[$((token - 1))]}")
  done
  ((${#picked[@]})) && printf '%s\n' "${picked[@]}" || true
}

# Interactive selection — only reached on a standalone attended run with no
# targets (main() handles the other paths). Enter cancels: nothing wiped.
wipe_select_disks() {
  local all_disks=("$@")
  echo -e "  ${BOLD}Select the disk(s) to wipe.${NC}"
  echo -e "  Enter the index number(s) to wipe (space-separated), or" \
          "${BOLD}all${NC}."
  echo -e "  Press ${BOLD}Enter${NC} with no input to" \
          "${YELLOW}cancel${NC} — nothing is wiped by default."
  echo ""
  local selection
  read -rp "  Wipe which disk(s)? (e.g. '1 3', 'all', Enter to cancel): " \
    selection
  mapfile -t DISKS_TO_WIPE < <(wipe_parse_selection "$selection" \
    "${all_disks[@]}")
}
