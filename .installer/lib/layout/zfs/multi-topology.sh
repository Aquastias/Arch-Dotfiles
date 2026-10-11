#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/multi-topology.sh — multi-disk topology choices
# =============================================================================
# Used by: lib/layout/zfs/multi.sh (sources it). Suggests and resolves the OS
# pool and storage-group topologies (prompting when the config leaves them
# open) and, for topology=none, folds or splits the leftover OS disks.
# Writes the _LAYOUT_IMPL_* record declared in multi.sh.
# =============================================================================

# =============================================================================
# OS TOPOLOGY SUGGESTIONS
# =============================================================================

layout_suggest_os_topologies() {
  # Prints one suggested topology per line, recommended first.
  # 'none' = install on one disk, no RAID; other disks fold into dpool.
  local count="$1"
  if ((count == 1)); then
    echo "none  (only option for 1 disk — no RAID possible)"
    return
  fi
  echo "mirror  ← recommended  (RAID-1: 1 failure tolerance," \
       "half capacity)"
  echo "stripe  (RAID-0: full speed/capacity, no redundancy" \
       "— not for OS)"
  echo "none  (no RAID: pick one disk for OS," \
       "rest go to dpool as storage)"
}

# =============================================================================
# STORAGE TOPOLOGY SUGGESTIONS
# =============================================================================

layout_suggest_storage_topologies() {
  # Prints topology suggestions for a storage group based on disk count.
  local count="$1"
  case "$count" in
  1)
    echo "independent  ← recommended  (single disk, its own vdev)"
    echo "stripe  (alias for independent with 1 disk)"
    ;;
  2)
    echo "mirror  ← recommended  (RAID-1, full redundancy, 1× usable)"
    echo "stripe  (RAID-0, combined capacity, no redundancy)"
    echo "independent  (each disk its own vdev, no cross-disk redundancy)"
    ;;
  3)
    echo "raidz1  ← recommended  (RAID-Z1/RAID-5: 1 parity, 2× usable)"
    echo "mirror  (requires even count — less ideal for 3 disks)"
    echo "stripe  (no redundancy)"
    echo "independent  (each disk its own vdev)"
    ;;
  4)
    echo "raidz1  ← recommended  (1 parity disk, 3× usable)"
    echo "raidz2  (2 parity disks, 2× usable, survives 2 failures)"
    echo "mirror  (2 × 2-disk mirrors)"
    echo "stripe  (no redundancy)"
    echo "independent  (each disk its own vdev)"
    ;;
  5)
    echo "raidz2  ← recommended  (2 parity disks, 3× usable," \
         "2 failures)"
    echo "raidz1  (1 parity disk, 4× usable)"
    echo "stripe  (no redundancy)"
    echo "independent  (each disk its own vdev)"
    ;;
  *)
    echo "raidz2  ← recommended  (good balance of redundancy and capacity)"
    echo "raidz1  (less redundancy, more usable space)"
    echo "stripe  (no redundancy)"
    echo "mirror  (best for even disk counts)"
    echo "independent  (each disk its own vdev)"
    ;;
  esac
}

# =============================================================================
# OS TOPOLOGY RESOLUTION
# =============================================================================

layout_resolve_os_topology() {
  section "Resolving OS Pool Topology"

  local configured_topology disk all_os=()
  configured_topology="$(config_optional '.os_pool.topology')"
  while IFS= read -r disk; do all_os+=("$disk"); done \
    < <(jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]')

  if [[ -n "$configured_topology" ]]; then
    # Topology set in config — use it directly without prompting
    _LAYOUT_IMPL_OS_TOPOLOGY="$configured_topology"
    info "OS topology from config: ${_LAYOUT_IMPL_OS_TOPOLOGY}"
  else
    _zfs_multi_topology_ask_os_topology "${all_os[@]}"
  fi

  # topology=none: pick one install disk, fold the rest into dpool
  [[ "$_LAYOUT_IMPL_OS_TOPOLOGY" == "none" ]] || return 0
  _zfs_multi_topology_pick_os_disk "${all_os[@]}"
}

# _zfs_multi_topology_print_disks <disk>... — one "<disk>  (<size>)" line each.
_zfs_multi_topology_print_disks() {
  local disk size
  for disk in "$@"; do
    size="$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')"
    printf "    %s  (%s)\n" "$disk" "$size"
  done
}

# Auto-suggest based on disk count and let the operator choose.
_zfs_multi_topology_ask_os_topology() {
  local disk_count="$#" line choices=()
  echo -e "\n  ${BOLD}OS pool — ${disk_count} disk(s):${NC}"
  _zfs_multi_topology_print_disks "$@"
  while IFS= read -r line; do choices+=("$line"); done \
    < <(layout_suggest_os_topologies "$disk_count")
  pick_option "Choose OS pool topology:" "${choices[@]}"
  _LAYOUT_IMPL_OS_TOPOLOGY="$PICK_RESULT"
  info "OS topology selected: ${_LAYOUT_IMPL_OS_TOPOLOGY}"
}

# topology=none: one disk takes the OS; every other listed OS disk becomes a
# storage leftover.
_zfs_multi_topology_pick_os_disk() {
  local all_os=("$@") disk size model disk_choices=()
  if (($# == 1)); then
    # Only one disk listed — no choice needed
    _LAYOUT_IMPL_OS_DISK="${all_os[0]}"
    _LAYOUT_IMPL_LEFTOVER_DISKS=()
    info "Single OS disk (no RAID): ${_LAYOUT_IMPL_OS_DISK}"
    return 0
  fi
  echo ""
  echo -e "  ${BOLD}Select the disk to install the OS on:${NC}"
  for disk in "${all_os[@]}"; do
    size="$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')"
    model="$(lsblk -dno MODEL "$disk" 2>/dev/null | join_words || echo '')"
    disk_choices+=("${disk}  ${size}  ${model}")
  done
  pick_option "Install OS on which disk?" "${disk_choices[@]}"
  _LAYOUT_IMPL_OS_DISK="$PICK_RESULT"

  _LAYOUT_IMPL_LEFTOVER_DISKS=()
  for disk in "${all_os[@]}"; do
    [[ "$disk" != "$_LAYOUT_IMPL_OS_DISK" ]] \
      && _LAYOUT_IMPL_LEFTOVER_DISKS+=("$disk")
  done

  info "OS install disk   : ${_LAYOUT_IMPL_OS_DISK}"
  ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)) &&
    info "Leftover → dpool  : ${_LAYOUT_IMPL_LEFTOVER_DISKS[*]}"
  return 0
}

# =============================================================================
# STORAGE TOPOLOGY RESOLUTION
# =============================================================================

layout_resolve_storage_topologies() {
  section "Resolving Storage Topologies"

  # ── Config-defined storage groups ─────────────────────────────────────────
  local storage_group_count
  storage_group_count="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  local i
  for ((i = 0; i < storage_group_count; i++)); do
    local name
    name="$(config_required ".storage_groups[$i].name")"
    local disk_count
    disk_count="$(jsonc "$CONFIG_FILE" \
      | jq ".storage_groups[$i].disks | length")"
    local topology
    topology="$(config_optional ".storage_groups[$i].topology")"

    if [[ -n "$topology" ]]; then
      _LAYOUT_IMPL_TOPOLOGIES["$name"]="$topology"
      info "Group '${name}' (${disk_count} disk(s)): topology '${topology}'" \
           "(from config)"
    else
      local choices=()
      while IFS= read -r line; do choices+=("$line"); done \
        < <(layout_suggest_storage_topologies "$disk_count")
      echo -e "\n  ${BOLD}Storage group '${name}' — ${disk_count} disk(s):${NC}"
      while IFS= read -r disk; do
        local size
        size="$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')"
        printf "    %s  (%s)\n" "$disk" "$size"
      done < <(jsonc "$CONFIG_FILE" | jq -r ".storage_groups[$i].disks[]")
      pick_option "Choose topology for '${name}':" "${choices[@]}"
      _LAYOUT_IMPL_TOPOLOGIES["$name"]="$PICK_RESULT"
      info "Group '${name}': topology '${PICK_RESULT}' (selected)"
    fi
  done
  # Leftover OS disks (topology=none) are handled per-disk in
  # layout_resolve_leftover_disks (ADR 0027, issue 05), not as one group here.
}

# =============================================================================
# STANDALONE DATA POOL RESOLUTION (ADR 0027)
# =============================================================================

# =============================================================================
# INTERACTIVE LEFTOVER DISKS (ADR 0027, issue 05)
# =============================================================================
# ZFS-multi-specific: when OS topology is `none`, each leftover OS disk is
# folded into the Combined Data Pool or synthesised as its own Standalone Data
# Pool via layout_add_data_pool (the shared record verb in
# lib/layout/data-pools.sh).

_zfs_multi_topology_next_default_pool_name() {
  # Lowest unused dataN name (data1, data2, …), skipping names already in the
  # data-pool structure (declarative entries + earlier interactive choices).
  local number=1 candidate existing_name taken
  while true; do
    candidate="data${number}"
    taken=false
    for existing_name in "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"; do
      [[ "$existing_name" == "$candidate" ]] && { taken=true; break; }
    done
    $taken || { printf '%s' "$candidate"; return; }
    ((number++))
  done
}

_zfs_multi_topology_read_tty() {
  # Overridable single-line reader (stubbed in tests). Prompt goes to the
  # terminal; the entered value is echoed to stdout.
  local __answer
  read -rp "$1" __answer </dev/tty
  printf '%s' "$__answer"
}

layout_prompt_pool_name() {
  # Prompts for a Standalone Data Pool name, looping until it passes
  # zfs_valid_pool_name and is not already taken; empty input accepts the
  # default. Sets POOL_NAME_RESULT. Honors INSTALL_UNATTENDED (uses default).
  # Usage: layout_prompt_pool_name <default> [taken_name...]
  local default_name="$1"
  shift
  local taken=("$@")
  if [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    POOL_NAME_RESULT="$default_name"
    info "Auto pool name (unattended): ${default_name}"
    return
  fi
  local name reason existing_name clash
  while true; do
    name="$(_zfs_multi_topology_read_tty "  Pool name [${default_name}]: ")"
    [[ -z "$name" ]] && name="$default_name"
    if ! reason="$(zfs_valid_pool_name "$name")"; then
      warn "Invalid pool name: ${reason}"
      continue
    fi
    clash=false
    for existing_name in "${taken[@]}"; do
      [[ "$existing_name" == "$name" ]] && { clash=true; break; }
    done
    if $clash; then
      warn "Pool name '${name}' is already taken — choose another."
      continue
    fi
    # shellcheck disable=SC2034 # the caller reads POOL_NAME_RESULT
    POOL_NAME_RESULT="$name"
    return
  done
}

layout_resolve_leftover_disks() {
  # Per-disk fold-vs-own-pool choice for leftover OS disks (topology=none with
  # 2+ OS disks). Fold → the Combined Data Pool 'dpool' (today's behaviour).
  # Own-pool → a single-disk stripe Standalone Data Pool synthesized into the
  # same structure declarative data_pools[] use. Folded disks then keep the
  # group-wide topology prompt. (ADR 0027, issue 05.)
  ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)) || return 0
  section "Resolving Leftover Disks"

  local rpool_name disk size folded=()
  rpool_name="$(config_required '.os_pool.pool_name')"
  for disk in "${_LAYOUT_IMPL_LEFTOVER_DISKS[@]}"; do
    size="$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')"
    # Ask the Leftover-Disk Adapter (plan.sh) rather than prompting directly, so
    # the planner stays pure and tests can substitute a non-interactive adapter.
    layout_leftover_choice "$disk" "$size"
    if [[ "$LAYOUT_LEFTOVER_CHOICE" == "own" ]]; then
      _zfs_multi_topology_leftover_own_pool "$disk" "$rpool_name"
    else
      folded+=("$disk")
      info "Leftover ${disk} → Combined Data Pool 'dpool'"
    fi
  done

  # Only the folded disks remain as dpool leftovers; keep today's group-wide
  # topology choice for them (partition/create consume _LAYOUT_IMPL_LEFTOVER_*).
  _LAYOUT_IMPL_LEFTOVER_DISKS=("${folded[@]}")
  ((${#folded[@]} > 0)) || return 0
  _zfs_multi_topology_ask_leftover_topology "${folded[@]}"
}

# A leftover disk becomes its own zfs Standalone Data Pool (it shares the OS
# disk's ZFS-ness; non-zfs leftovers are not synthesised here).
_zfs_multi_topology_leftover_own_pool() {
  local disk="$1" rpool_name="$2" default_name pool_name
  default_name="$(_zfs_multi_topology_next_default_pool_name)"
  layout_leftover_pool_name "$default_name" "$rpool_name" dpool \
    "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"
  pool_name="$LAYOUT_LEFTOVER_POOL_NAME"
  layout_add_data_pool "$pool_name" stripe "/data/${pool_name}" 12 zfs false \
    "$disk"
  info "Leftover ${disk} → standalone pool '${pool_name}'" \
       "(stripe → /data/${pool_name})"
}

_zfs_multi_topology_ask_leftover_topology() {
  local leftover_count="$#" line choices=()
  while IFS= read -r line; do choices+=("$line"); done \
    < <(layout_suggest_storage_topologies "$leftover_count")
  echo -e "\n  ${BOLD}Folded leftover disks → dpool" \
          "(${leftover_count} disk(s)):${NC}"
  _zfs_multi_topology_print_disks "$@"
  pick_option "Choose topology for folded leftover disks in dpool:" \
    "${choices[@]}"
  _LAYOUT_IMPL_TOPOLOGIES["_leftover"]="$PICK_RESULT"
  info "Folded leftover topology: ${PICK_RESULT}"
}

