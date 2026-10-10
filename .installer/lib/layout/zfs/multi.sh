#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/multi.sh — Multi-disk install layout
# =============================================================================
# Sourced by 03-install.sh when INSTALL_MODE=multi.
# Requires: lib/common.sh (for part_name), lib/zfs/pools.sh (for zfs_create_pool,
#           zfs_vdev_spec, zfs_ram_gib) already sourced.
#
# Provides:
#   layout_resolve_os_topology          — determines rpool topology; prompts if needed
#   layout_resolve_storage_topologies   — determines dpool group topologies; prompts
#   layout_partition_os_disks_multi     — partitions OS disk(s)
#   layout_partition_storage_disks_multi— partitions storage group disk(s)
#   layout_create_multi_rpool           — creates rpool with resolved topology
#   layout_create_multi_data_pool           — creates dpool with all storage groups
#   layout_resolve_data_pools           — reads data_pools[] into internal state
#   layout_resolve_leftover_disks       — per-disk fold-vs-own-pool for topology=none
#   layout_partition_data_pools         — partitions Standalone Data Pool disk(s)
#   layout_create_data_pools            — creates each Standalone Data Pool + dataset
#   layout_mount_multi_esps             — mounts primary + secondary ESPs
#   layout_validate  — seam: validates os_pool + storage_groups inputs
#   _layout_plan_mode — plan hook (for layout_plan in plan.sh): wraps
#                     layout_resolve_os_topology; layout_resolve_data_pools;
#                     layout_resolve_storage_topologies; layout_resolve_leftover_disks
#   _layout_os_disks  — plan hook: ordered OS disks (for ESP resolution)
#   layout_partition — seam: wraps layout_partition_os_disks_multi;
#                     layout_partition_storage_disks_multi
#   layout_create_pools   — seam: wraps layout_create_multi_rpool; layout_create_multi_data_pool
#   layout_mount_esp      — seam: wraps layout_mount_multi_esps
#
# INTERNAL STATE (do not reference outside this module):
#   _LAYOUT_IMPL_ESP_PARTS[]         — ESP partitions on OS disks
#   _LAYOUT_IMPL_ZFS_PARTS[]         — ZFS partitions on OS disks (for rpool)
#   _LAYOUT_IMPL_OS_DISK          — chosen single OS disk (topology=none only)
#   _LAYOUT_IMPL_OS_TOPOLOGY      — resolved topology string
#   _LAYOUT_IMPL_LEFTOVER_DISKS[] — OS-list disks folded into dpool
#                                 (topology=none)
#   _LAYOUT_IMPL_STORAGE_PARTS[name]    — associative:
#                                         group name → "part1 part2 ..."
#   _LAYOUT_IMPL_TOPOLOGIES[]  — associative: group name → topology string
#   _LAYOUT_IMPL_DATA_POOL_NAMES[]  — ordered Standalone Data Pool names
#   _LAYOUT_IMPL_DATA_POOL_DISKS[]  — associative: pool name → "disk1 ..."
#   _LAYOUT_IMPL_DATA_POOL_TOPOLOGY[]   — associative: pool name → topology
#   _LAYOUT_IMPL_DATA_POOL_MOUNT[]  — associative: pool name → mountpoint
#   _LAYOUT_IMPL_DATA_POOL_ASHIFT[] — associative: pool name → ashift
#   _LAYOUT_IMPL_DATA_POOL_PARTS[]  — associative: pool name → "part1 ..."
# =============================================================================

# shellcheck source=./common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"
# layout_create_data_pools dispatches each group through the Data Group Formatter seam.
declare -F data_formatter_source >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../dispatch.sh"

_LAYOUT_IMPL_ESP_PARTS=()
_LAYOUT_IMPL_ZFS_PARTS=()
_LAYOUT_IMPL_OS_DISK=""
_LAYOUT_IMPL_OS_TOPOLOGY=""
_LAYOUT_IMPL_LEFTOVER_DISKS=()
declare -gA _LAYOUT_IMPL_STORAGE_PARTS
declare -gA _LAYOUT_IMPL_TOPOLOGIES
# The Standalone Data Pool record + resolve/partition/create pipeline lives in
# the root-fs-agnostic orchestrator (lib/layout/data-pools.sh, sourced by core);
# this adapter's seam verbs call it, and the interactive leftover synthesis below
# appends to it via layout_add_data_pool.

# Out-param for layout_prompt_pool_name (mirrors PICK_RESULT house style).
POOL_NAME_RESULT=""

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

  local configured_topology
  configured_topology="$(config_optional '.os_pool.topology')"
  local all_os=()
  while IFS= read -r disk; do all_os+=("$disk"); done \
    < <(jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]')
  local disk_count="${#all_os[@]}"

  if [[ -n "$configured_topology" ]]; then
    # Topology set in config — use it directly without prompting
    _LAYOUT_IMPL_OS_TOPOLOGY="$configured_topology"
    info "OS topology from config: ${_LAYOUT_IMPL_OS_TOPOLOGY}"
  else
    # Auto-suggest based on disk count and let user choose
    echo -e "\n  ${BOLD}OS pool — ${disk_count} disk(s):${NC}"
    for disk in "${all_os[@]}"; do
      local size
      size="$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')"
      printf "    %s  (%s)\n" "$disk" "$size"
    done
    local choices=()
    while IFS= read -r line; do choices+=("$line"); done \
      < <(layout_suggest_os_topologies "$disk_count")
    pick_option "Choose OS pool topology:" "${choices[@]}"
    _LAYOUT_IMPL_OS_TOPOLOGY="$PICK_RESULT"
    info "OS topology selected: ${_LAYOUT_IMPL_OS_TOPOLOGY}"
  fi

  # topology=none: pick one install disk, fold the rest into dpool
  if [[ "$_LAYOUT_IMPL_OS_TOPOLOGY" == "none" ]]; then
    if ((disk_count == 1)); then
      # Only one disk listed — no choice needed
      _LAYOUT_IMPL_OS_DISK="${all_os[0]}"
      _LAYOUT_IMPL_LEFTOVER_DISKS=()
      info "Single OS disk (no RAID): ${_LAYOUT_IMPL_OS_DISK}"
    else
      echo ""
      echo -e "  ${BOLD}Select the disk to install the OS on:${NC}"
      local disk_choices=()
      for disk in "${all_os[@]}"; do
        local size
        size="$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')"
        local model
        model="$(lsblk -dno MODEL "$disk" 2>/dev/null | xargs || echo '')"
        disk_choices+=("${disk}  ${size}  ${model}")
      done
      pick_option "Install OS on which disk?" "${disk_choices[@]}"
      _LAYOUT_IMPL_OS_DISK="$PICK_RESULT"

      # All other listed OS disks become storage leftovers
      _LAYOUT_IMPL_LEFTOVER_DISKS=()
      for disk in "${all_os[@]}"; do
        [[ "$disk" != "$_LAYOUT_IMPL_OS_DISK" ]] \
          && _LAYOUT_IMPL_LEFTOVER_DISKS+=("$disk")
      done

      info "OS install disk   : ${_LAYOUT_IMPL_OS_DISK}"
      ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)) &&
        info "Leftover → dpool  : ${_LAYOUT_IMPL_LEFTOVER_DISKS[*]}"
    fi
  fi
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
    disk_count="$(jsonc "$CONFIG_FILE" | jq ".storage_groups[$i].disks | length")"
    local topology
    topology="$(config_optional ".storage_groups[$i].topology")"

    if [[ -n "$topology" ]]; then
      _LAYOUT_IMPL_TOPOLOGIES["$name"]="$topology"
      info "Group '${name}' (${disk_count} disk(s)): topology '${topology}' (from config)"
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
# ZFS-multi-specific: when OS topology is `none`, each leftover OS disk is folded
# into the Combined Data Pool or synthesised as its own Standalone Data Pool via
# layout_add_data_pool (the shared record verb in lib/layout/data-pools.sh).

_zfs_multi_next_default_pool_name() {
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

_zfs_multi_read_tty() {
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
    name="$(_zfs_multi_read_tty "  Pool name [${default_name}]: ")"
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

  local rpool_name
  rpool_name="$(config_required '.os_pool.pool_name')"

  local all=("${_LAYOUT_IMPL_LEFTOVER_DISKS[@]}")
  local folded=()
  local disk
  for disk in "${all[@]}"; do
    local size
    size="$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')"
    # Ask the Leftover-Disk Adapter (plan.sh) rather than prompting directly, so
    # the planner stays pure and tests can substitute a non-interactive adapter.
    layout_leftover_choice "$disk" "$size"
    if [[ "$LAYOUT_LEFTOVER_CHOICE" == "own" ]]; then
      local def
      def="$(_zfs_multi_next_default_pool_name)"
      layout_leftover_pool_name "$def" "$rpool_name" dpool \
        "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"
      local pool_name="$LAYOUT_LEFTOVER_POOL_NAME"
      # A folded leftover disk becomes its own zfs pool (it shares the OS disk's
      # ZFS-ness; non-zfs leftovers are not synthesised here).
      layout_add_data_pool "$pool_name" stripe "/data/${pool_name}" 12 zfs false "$disk"
      info "Leftover ${disk} → standalone pool '${pool_name}' (stripe → /data/${pool_name})"
    else
      folded+=("$disk")
      info "Leftover ${disk} → Combined Data Pool 'dpool'"
    fi
  done

  # Only the folded disks remain as dpool leftovers; keep today's group-wide
  # topology choice for them (partition/create consume _LAYOUT_IMPL_LEFTOVER_*).
  _LAYOUT_IMPL_LEFTOVER_DISKS=("${folded[@]}")
  ((${#folded[@]} > 0)) || return 0

  local leftover_count="${#folded[@]}"
  local choices=()
  while IFS= read -r line; do choices+=("$line"); done \
    < <(layout_suggest_storage_topologies "$leftover_count")
  echo -e "\n  ${BOLD}Folded leftover disks → dpool (${leftover_count} disk(s)):${NC}"
  for disk in "${folded[@]}"; do
    local size
    size="$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')"
    printf "    %s  (%s)\n" "$disk" "$size"
  done
  pick_option "Choose topology for folded leftover disks in dpool:" "${choices[@]}"
  _LAYOUT_IMPL_TOPOLOGIES["_leftover"]="$PICK_RESULT"
  info "Folded leftover topology: ${PICK_RESULT}"
}

# =============================================================================
# PARTITIONING
# =============================================================================

layout_partition_os_disks_multi() {
  section "Partitioning OS Disk(s)"
  local esp_size
  esp_size="$(layout_resolve_esp_size)"
  _LAYOUT_IMPL_ESP_PARTS=()
  _LAYOUT_IMPL_ZFS_PARTS=()

  # When topology=none, only the chosen disk goes into rpool
  local rpool_disks=()
  if [[ "$_LAYOUT_IMPL_OS_TOPOLOGY" == "none" ]]; then
    rpool_disks=("$_LAYOUT_IMPL_OS_DISK")
  else
    while IFS= read -r d; do rpool_disks+=("$d"); done \
      < <(jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]')
  fi

  local disk
  for disk in "${rpool_disks[@]}"; do
    info "Partitioning OS disk: $disk"
    # Wipe + zap + create the ESP (partition 1) — shared with the single ritual.
    layout_zfs_partition_esp_start "$disk" "$esp_size"
    # p2 — ZFS rpool (rest of disk)
    sgdisk -n2:0:0 -t2:bf00 -c2:"ZFS rpool" "$disk"
    partprobe "$disk"
    _LAYOUT_IMPL_ESP_PARTS+=("$(part_name "$disk" 1)")
    _LAYOUT_IMPL_ZFS_PARTS+=("$(part_name "$disk" 2)")
  done

  sleep 2
  local i
  for i in "${!_LAYOUT_IMPL_ESP_PARTS[@]}"; do
    mkfs.fat -F32 -n "EFI$((i + 1))" "${_LAYOUT_IMPL_ESP_PARTS[$i]}"
    info "Formatted ESP $((i + 1)): ${_LAYOUT_IMPL_ESP_PARTS[$i]}"
  done
  # LAYOUT_ESP_PARTS is published by layout_plan (ADR 0034); partitioning just
  # creates and formats the partitions whose paths the plan already resolved.
}

layout_partition_storage_disks_multi() {
  section "Partitioning Storage Disk(s)"

  # Config-defined storage groups
  local storage_group
  storage_group="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  local i
  for ((i = 0; i < storage_group; i++)); do
    local name
    name="$(config_required ".storage_groups[$i].name")"
    local parts=()
    while IFS= read -r disk; do
      info "Partitioning storage disk: $disk  (group: ${name})"
      wipefs -af "$disk"
      sgdisk --zap-all "$disk"
      sgdisk -n1:0:0 -t1:bf00 -c1:"ZFS dpool-${name}" "$disk"
      partprobe "$disk"
      parts+=("$(part_name "$disk" 1)")
    done < <(jsonc "$CONFIG_FILE" | jq -r ".storage_groups[$i].disks[]")
    _LAYOUT_IMPL_STORAGE_PARTS["$name"]="${parts[*]}"
  done

  # Leftover OS disks (topology=none, 2+ OS disks listed)
  if ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)); then
    local lparts=()
    local disk
    for disk in "${_LAYOUT_IMPL_LEFTOVER_DISKS[@]}"; do
      info "Partitioning leftover OS disk → dpool: $disk"
      wipefs -af "$disk"
      sgdisk --zap-all "$disk"
      sgdisk -n1:0:0 -t1:bf00 -c1:"ZFS dpool-extra" "$disk"
      partprobe "$disk"
      lparts+=("$(part_name "$disk" 1)")
    done
    _LAYOUT_IMPL_STORAGE_PARTS["_leftover"]="${lparts[*]}"
  fi

  sleep 2
  info "Storage partitioning complete."
}

# =============================================================================
# ZFS POOL CREATION
# =============================================================================

layout_create_multi_rpool() {
  section "Creating OS Pool (rpool)"
  zfs_encryption_options

  local pool_name
  pool_name="$(config_required '.os_pool.pool_name')"
  local ashift; ashift="$(install_config_os_pool_ashift)"

  local vdev_spec
  vdev_spec="$(zfs_vdev_spec "${_LAYOUT_IMPL_OS_TOPOLOGY}" \
    "${_LAYOUT_IMPL_ZFS_PARTS[@]}")"

  info "Pool: ${pool_name}  topology: ${_LAYOUT_IMPL_OS_TOPOLOGY}"
  info "vdev: ${vdev_spec}"

  # SC2086 (intentional): vdev_spec must be word-split into multiple args
  # for zfs_create_pool (e.g. "mirror /dev/sda1 /dev/sdb1" → 3 args). Built
  # from controlled inputs in zfs_vdev_spec, so word-splitting is safe.
  # shellcheck disable=SC2086
  zfs_create_pool "${pool_name}" "${ashift}" $vdev_spec
  zfs_create_os_datasets "${pool_name}"
}

layout_create_multi_data_pool() {
  section "Creating Data Pool (dpool)"

  local storage_group
  storage_group="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  local has_left=false
  [[ -v "_LAYOUT_IMPL_STORAGE_PARTS[_leftover]" ]] && has_left=true

  if ((storage_group == 0)) && ! $has_left; then
    info "No storage groups and no leftover disks — skipping dpool."
    return
  fi
  zfs_encryption_options

  # Collect vdev specs from all groups
  local all_vdevs=()
  local i
  for ((i = 0; i < storage_group; i++)); do
    local name
    name="$(config_required ".storage_groups[$i].name")"
    local topology="${_LAYOUT_IMPL_TOPOLOGIES[$name]:-stripe}"
    local parts
    read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[$name]}"
    local vdev_spec
    vdev_spec="$(zfs_vdev_spec "$topology" "${parts[@]}")"
    # SC2206 (intentional): vs is a single string built from zfs_vdev_spec
    # output that we want word-split into separate vdev tokens (e.g.
    # "mirror /dev/sdb1 /dev/sdc1" → 3 array elements).
    # shellcheck disable=SC2206
    all_vdevs+=($vdev_spec)
    info "  Group '${name}': ${topology}  [${parts[*]}]"
  done

  if $has_left; then
    local topology="${_LAYOUT_IMPL_TOPOLOGIES[_leftover]:-independent}"
    local parts
    read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[_leftover]}"
    local vdev_spec
    vdev_spec="$(zfs_vdev_spec "$topology" "${parts[@]}")"
    # shellcheck disable=SC2206  # see comment in loop above
    all_vdevs+=($vdev_spec)
    info "  Group '_leftover': ${topology}  [${parts[*]}]"
  fi

  # Use the first storage group's ashift (all storage disks ideally match)
  local pashift; pashift="$(install_config_storage_group_ashift 0)"

  # SC2068 (intentional): all_vdevs holds pre-tokenised vdev spec elements
  # that must each become a separate argument to zpool create. Names are
  # internally generated so word-splitting is safe.
  # shellcheck disable=SC2068
  zfs_create_pool "dpool" "${pashift}" ${all_vdevs[@]}

  # ── Datasets ───────────────────────────────────────────────────────────────
  zfs create -o canmount=off -o mountpoint=none dpool/DATA

  # One dataset per config-defined group
  for ((i = 0; i < storage_group; i++)); do
    local name
    name="$(config_required ".storage_groups[$i].name")"
    local mountpoint
    mountpoint="$(config_required ".storage_groups[$i].mount")"
    local topology="${_LAYOUT_IMPL_TOPOLOGIES[$name]:-stripe}"

    if [[ "$topology" == "independent" ]]; then
      # Per-disk sub-datasets so each disk can be managed separately
      zfs create -o canmount=off -o mountpoint=none "dpool/DATA/${name}"
      local parts
      read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[$name]}"
      local j
      for j in "${!parts[@]}"; do
        zfs create \
          -o mountpoint="${mountpoint}/disk$((j + 1))" \
          "dpool/DATA/${name}/disk$((j + 1))"
        info "  dpool/DATA/${name}/disk$((j + 1)) → ${mountpoint}/disk$((j + 1))"
      done
    else
      zfs create -o mountpoint="${mountpoint}" "dpool/DATA/${name}"
      info "  dpool/DATA/${name} → ${mountpoint}"
    fi
  done

  # Dataset(s) for leftover OS disks
  if $has_left; then
    local topology="${_LAYOUT_IMPL_TOPOLOGIES[_leftover]:-independent}"
    if [[ "$topology" == "independent" ]]; then
      zfs create -o canmount=off -o mountpoint=none "dpool/DATA/extra"
      local parts
      read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[_leftover]}"
      local j
      for j in "${!parts[@]}"; do
        zfs create \
          -o mountpoint="/data/extra/disk$((j + 1))" \
          "dpool/DATA/extra/disk$((j + 1))"
        info "  dpool/DATA/extra/disk$((j + 1)) → /data/extra/disk$((j + 1))"
      done
    else
      zfs create -o mountpoint="/data/extra" "dpool/DATA/extra"
      info "  dpool/DATA/extra → /data/extra"
    fi
  fi

  info "dpool created."
}

# =============================================================================
# ESP MOUNTING
# =============================================================================

layout_mount_multi_esps() {
  section "Mounting ESP(s)"

  # Primary ESP (first OS disk) → /boot/efi
  mkdir -p "${MOUNT_ROOT}/boot/efi"
  mount "${_LAYOUT_IMPL_ESP_PARTS[0]}" "${MOUNT_ROOT}/boot/efi"
  info "Primary ESP: ${_LAYOUT_IMPL_ESP_PARTS[0]} → /boot/efi"

  # Secondary ESPs → /boot/efi1, /boot/efi2, ...
  local i
  for i in $(seq 1 $((${#_LAYOUT_IMPL_ESP_PARTS[@]} - 1))); do
    mkdir -p "${MOUNT_ROOT}/boot/efi${i}"
    mount "${_LAYOUT_IMPL_ESP_PARTS[$i]}" "${MOUNT_ROOT}/boot/efi${i}"
    info "Secondary ESP ${i}: ${_LAYOUT_IMPL_ESP_PARTS[$i]} → /boot/efi${i}"
  done
}

# =============================================================================
# VALIDATION HELPERS (issue 03/04)
# =============================================================================

# layout_disk_exists is the shared disk-existence seam from lib/layout/core.sh
# (sourced via zfs/common.sh); multi's existence checks call it directly.

_zfs_multi_declared_users() {
  # Seam: declared usernames (space-separated, Primary User first) used to
  # validate `owners` lists. Reads the resolved host config; overridable in
  # unit tests so the owners checks don't need a real host config on disk.
  _pool_owners_declared_users
}

_zfs_multi_validate_owners() {
  # Aborts the install when <owners> is invalid (pool-owners, ADR 0031): a
  # bare name must be a declared user; an @group must have ≥1 declared member.
  # No-op when owners is omitted — that case defaults to the Primary User, or
  # is left root-owned with a warning on a host with no declared users.
  local label="$1" owners="$2"
  [[ -n "${owners// }" ]] || return 0
  local reason
  reason="$(zfs_pool_owners_validate "$owners" "$(_zfs_multi_declared_users)" \
    "$(_zfs_multi_group_map)")" \
    || error "${label} ${reason}"
}

_zfs_multi_group_map() {
  # Seam: "group:member1,member2" pairs for @group owners validation. Built
  # from User Configs; overridable in unit tests.
  _pool_owners_group_map
}

_zfs_multi_mount_is_reserved() {
  # Returns 0 when the mountpoint shadows an OS/reserved dataset, so a data
  # pool can't break boot. Subtree semantics (not bare prefix): /var and
  # /boot match their whole subtree; /data, /variable etc. are free.
  case "$1" in
  / | /home | /tmp | /persist) return 0 ;;
  /var | /var/* | /boot | /boot/*) return 0 ;;
  esac
  return 1
}

# =============================================================================
# LAYOUT INTERFACE (called by 03-install.sh)
# =============================================================================

layout_validate() {
  layout_enter_phase validate
  layout_validate_esp_size
  local topology
  topology="$(config_optional '.os_pool.topology')"
  if [[ -n "$topology" ]]; then
    case "$topology" in
    mirror | stripe | none) ;;
    *) error "os_pool.topology must be mirror|stripe|none, got: '${topology}'" ;;
    esac
  fi

  local disk_count
  disk_count="$(jsonc_strip "$CONFIG_FILE" | jq '.os_pool.disks | length')"
  ((disk_count >= 1)) || error "os_pool.disks must list at least 1 disk."

  local disk
  while IFS= read -r disk; do
    layout_disk_exists "$disk" || error "OS disk not found: $disk"
  done < <(jsonc_strip "$CONFIG_FILE" | jq -r '.os_pool.disks[]')

  local storage_group group_name gdc i
  storage_group="$(jsonc_strip "$CONFIG_FILE" | jq '.storage_groups | length')"
  for ((i = 0; i < storage_group; i++)); do
    group_name="$(config_required ".storage_groups[$i].name")"
    gdc="$(jsonc_strip "$CONFIG_FILE" \
      | jq ".storage_groups[$i].disks | length")"
    ((gdc >= 1)) || error "Storage group '${group_name}' has no disks."
    while IFS= read -r disk; do
      layout_disk_exists "$disk" || error "Group '${group_name}' disk not found: $disk"
    done < <(jsonc_strip "$CONFIG_FILE" | jq -r ".storage_groups[$i].disks[]")
    _zfs_multi_validate_owners "Storage group '${group_name}'" \
      "$(install_config_storage_group_owners "$i" | tr '\n' ' ')"
  done

  # Standalone Data Pools (ADR 0027): topology must match the disk count and
  # cannot be none/independent. Pure check — no disk is touched here.
  local data_pool data_name data_topology ddc reason
  data_pool="$(jsonc_strip "$CONFIG_FILE" | jq '(.data_pools // []) | length')"
  for ((i = 0; i < data_pool; i++)); do
    data_name="$(config_required ".data_pools[$i].name")"
    if ! reason="$(zfs_valid_pool_name "$data_name")"; then
      error "Data pool: ${reason}"
    fi
    data_topology="$(jsonc_strip "$CONFIG_FILE" \
      | jq -r ".data_pools[$i].topology // \"stripe\"")"
    ddc="$(jsonc_strip "$CONFIG_FILE" \
      | jq "(.data_pools[$i].disks // []) | length")"
    # Filesystem-aware: a non-zfs pool carries a native topology (e.g. btrfs
    # raid1) the zfs vdev validator doesn't know; its validity is gated by
    # validation.sh, so the dispatch passes it through here (ADR 0043).
    local dfs
    dfs="$(install_config_data_pool_filesystem "$i")"
    if ! reason="$(zfs_data_pool_topology_ok "$dfs" "$data_topology" "$ddc")"; then
      error "Data pool '${data_name}': ${reason}"
    fi
    _zfs_multi_validate_owners "Data pool '${data_name}'" \
      "$(install_config_data_pool_owners "$i" | tr '\n' ' ')"
  done

  # Cross-cutting data-pool guards (only when data_pools are declared, so
  # existing multi configs without them are untouched).
  if ((data_pool > 0)); then
    # Pool-name uniqueness across rpool + the Combined Data Pool (dpool) +
    # every Standalone Data Pool.
    local rpool_name dup
    rpool_name="$(config_required '.os_pool.pool_name')"
    dup="$( { printf '%s\n' "$rpool_name" dpool
              jsonc_strip "$CONFIG_FILE" | jq -r '.data_pools[].name'
            } | sort | uniq -d | head -1)"
    [[ -z "$dup" ]] || error "Duplicate pool name '${dup}': names must be" \
      "unique across rpool, dpool, and all data_pools."

    # Disk reuse across OS pool, storage groups, and data pools.
    local data_disk
    data_disk="$(jsonc_strip "$CONFIG_FILE" | jq -r '
      [ (.os_pool.disks // [])[],
        (.storage_groups[]?.disks // [])[],
        (.data_pools[]?.disks // [])[] ] | .[]' \
      | sort | uniq -d | head -1)"
    [[ -z "$data_disk" ]] || error "Disk '${data_disk}' is used in more than one" \
      "place (OS pool / storage group / data pool)."

    # Mount rules over all declared storage mounts (storage groups + data
    # pools, the latter defaulting to /data/<name>). None may shadow a
    # reserved OS path; no two may claim the same exact mountpoint. Nested
    # mounts (/data + /data/tank0) are fine — only exact dups are rejected.
    local mounts=() mountpoint mdup
    while IFS= read -r mountpoint; do
      [[ -n "$mountpoint" ]] && mounts+=("$mountpoint")
    done < <(jsonc_strip "$CONFIG_FILE" | jq -r '
      [ (.storage_groups[]? | .mount // empty),
        (.data_pools[]? | .mount // ("/data/" + .name)) ] | .[]')
    for mountpoint in "${mounts[@]}"; do
      ! _zfs_multi_mount_is_reserved "$mountpoint" \
        || error "Mountpoint '${mountpoint}' is reserved for the OS — choose another."
    done
    mdup="$(printf '%s\n' "${mounts[@]}" | sort | uniq -d | head -1)"
    [[ -z "$mdup" ]] || error "Mountpoint '${mdup}' is claimed by more than" \
      "one pool."

    # Every data-pool disk must exist before any destructive op (typo fails
    # safely). Last, so the name/topology/mount errors above surface first.
    for ((i = 0; i < data_pool; i++)); do
      data_name="$(config_required ".data_pools[$i].name")"
      while IFS= read -r disk; do
        layout_disk_exists "$disk" \
          || error "Data pool '${data_name}' disk not found: $disk"
      done < <(jsonc_strip "$CONFIG_FILE" | jq -r ".data_pools[$i].disks[]?")
    done
  fi
  layout_exit_phase validate
}

# Mode hooks for the unified layout_plan (plan.sh). Phase bracketing, ESP
# resolution and the plan contract are handled there.
_layout_plan_mode() {
  layout_resolve_os_topology
  # Declarative data_pools[] first, so interactive leftover naming can reject
  # collisions against them (uniqueness + default dataN numbering).
  layout_resolve_data_pools
  layout_resolve_storage_topologies
  layout_resolve_leftover_disks
  # Publish the pool-name record (consumed by chroot.sh, finalize.sh).
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_OS_POOL_NAME="$(config_required '.os_pool.pool_name')"
  # LAYOUT_DATA_POOL_NAMES: the Combined Data Pool (when storage groups or
  # folded leftovers exist) plus every Standalone Data Pool.
  # shellcheck disable=SC2034 # consumed by finalize.sh
  LAYOUT_DATA_POOL_NAMES=()
  local _storage_group_count
  _storage_group_count="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  if ((_storage_group_count > 0)) || ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)); then
    LAYOUT_DATA_POOL_NAMES+=("dpool")
  fi
  local _data_pool
  for _data_pool in "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"; do
    LAYOUT_DATA_POOL_NAMES+=("$_data_pool")
  done
}

# Ordered OS disks that receive an ESP — primary first. topology=none installs
# onto the one chosen disk; otherwise every os_pool disk is mirrored/striped and
# each gets an ESP. layout_resolve_os_topology (run by _layout_plan_mode) has set the
# topology + chosen disk by the time plan.sh asks.
_layout_os_disks() {
  if [[ "$_LAYOUT_IMPL_OS_TOPOLOGY" == "none" ]]; then
    printf '%s\n' "$_LAYOUT_IMPL_OS_DISK"
  else
    jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]'
  fi
}
layout_partition() {
  layout_enter_phase partition
  layout_partition_os_disks_multi
  layout_partition_storage_disks_multi
  layout_partition_data_pools
  layout_verify_partition_contract
  layout_exit_phase partition
}
layout_create_pools() {
  layout_enter_phase pools
  layout_create_multi_rpool
  layout_create_multi_data_pool
  layout_create_data_pools
  layout_exit_phase pools
}
layout_mount_esp() {
  layout_enter_phase esp
  layout_mount_multi_esps
  layout_exit_phase esp
}
