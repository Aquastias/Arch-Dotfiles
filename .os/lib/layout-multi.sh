#!/usr/bin/env bash
# =============================================================================
# lib/layout-multi.sh — Multi-disk install layout
# =============================================================================
# Sourced by 03-install.sh when INSTALL_MODE=multi.
# Requires: lib/common.sh (for part_name), lib/zfs-pools.sh (for _zpool_create,
#           build_vdev_spec, ram_gib) already sourced.
#
# Provides:
#   resolve_os_topology          — determines rpool topology; prompts if needed
#   resolve_storage_topologies   — determines dpool group topologies; prompts
#   partition_os_disks_multi     — partitions OS disk(s)
#   partition_storage_disks_multi— partitions storage group disk(s)
#   create_multi_rpool           — creates rpool with resolved topology
#   create_multi_dpool           — creates dpool with all storage groups
#   mount_multi_esps             — mounts primary + secondary ESPs
#   layout_plan      — seam: wraps resolve_os_topology;
#                     resolve_storage_topologies
#   layout_partition — seam: wraps partition_os_disks_multi;
#                     partition_storage_disks_multi
#   layout_create_pools   — seam: wraps create_multi_rpool; create_multi_dpool
#   layout_mount_esp      — seam: wraps mount_multi_esps
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
# =============================================================================

# shellcheck source=./layout-common.sh
source "${BASH_SOURCE[0]%/*}/layout-common.sh"

_LAYOUT_IMPL_ESP_PARTS=()
_LAYOUT_IMPL_ZFS_PARTS=()
_LAYOUT_IMPL_OS_DISK=""
_LAYOUT_IMPL_OS_TOPOLOGY=""
_LAYOUT_IMPL_LEFTOVER_DISKS=()
declare -gA _LAYOUT_IMPL_STORAGE_PARTS
declare -gA _LAYOUT_IMPL_TOPOLOGIES

# =============================================================================
# OS TOPOLOGY SUGGESTIONS
# =============================================================================

suggest_os_topologies() {
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

suggest_storage_topologies() {
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

resolve_os_topology() {
  section "Resolving OS Pool Topology"

  local cfg_topo
  cfg_topo="$(cfgo '.os_pool.topology')"
  local all_os=()
  while IFS= read -r d; do all_os+=("$d"); done \
    < <(jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]')
  local cnt="${#all_os[@]}"

  if [[ -n "$cfg_topo" ]]; then
    # Topology set in config — use it directly without prompting
    _LAYOUT_IMPL_OS_TOPOLOGY="$cfg_topo"
    info "OS topology from config: ${_LAYOUT_IMPL_OS_TOPOLOGY}"
  else
    # Auto-suggest based on disk count and let user choose
    echo -e "\n  ${BOLD}OS pool — ${cnt} disk(s):${NC}"
    for d in "${all_os[@]}"; do
      local s
      s="$(lsblk -dno SIZE "$d" 2>/dev/null || echo '?')"
      printf "    %s  (%s)\n" "$d" "$s"
    done
    local opts=()
    while IFS= read -r line; do opts+=("$line"); done \
      < <(suggest_os_topologies "$cnt")
    pick_option "Choose OS pool topology:" "${opts[@]}"
    _LAYOUT_IMPL_OS_TOPOLOGY="$PICK_RESULT"
    info "OS topology selected: ${_LAYOUT_IMPL_OS_TOPOLOGY}"
  fi

  # topology=none: pick one install disk, fold the rest into dpool
  if [[ "$_LAYOUT_IMPL_OS_TOPOLOGY" == "none" ]]; then
    if ((cnt == 1)); then
      # Only one disk listed — no choice needed
      _LAYOUT_IMPL_OS_DISK="${all_os[0]}"
      _LAYOUT_IMPL_LEFTOVER_DISKS=()
      info "Single OS disk (no RAID): ${_LAYOUT_IMPL_OS_DISK}"
    else
      echo ""
      echo -e "  ${BOLD}Select the disk to install the OS on:${NC}"
      local disk_opts=()
      for d in "${all_os[@]}"; do
        local s
        s="$(lsblk -dno SIZE "$d" 2>/dev/null || echo '?')"
        local m
        m="$(lsblk -dno MODEL "$d" 2>/dev/null | xargs || echo '')"
        disk_opts+=("${d}  ${s}  ${m}")
      done
      pick_option "Install OS on which disk?" "${disk_opts[@]}"
      _LAYOUT_IMPL_OS_DISK="$PICK_RESULT"

      # All other listed OS disks become storage leftovers
      _LAYOUT_IMPL_LEFTOVER_DISKS=()
      for d in "${all_os[@]}"; do
        [[ "$d" != "$_LAYOUT_IMPL_OS_DISK" ]] \
          && _LAYOUT_IMPL_LEFTOVER_DISKS+=("$d")
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

resolve_storage_topologies() {
  section "Resolving Storage Topologies"

  # ── Config-defined storage groups ─────────────────────────────────────────
  local sg_count
  sg_count="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  local i
  for ((i = 0; i < sg_count; i++)); do
    local name
    name="$(cfg ".storage_groups[$i].name")"
    local dc
    dc="$(jsonc "$CONFIG_FILE" | jq ".storage_groups[$i].disks | length")"
    local topo
    topo="$(cfgo ".storage_groups[$i].topology")"

    if [[ -n "$topo" ]]; then
      _LAYOUT_IMPL_TOPOLOGIES["$name"]="$topo"
      info "Group '${name}' (${dc} disk(s)): topology '${topo}' (from config)"
    else
      local opts=()
      while IFS= read -r line; do opts+=("$line"); done \
        < <(suggest_storage_topologies "$dc")
      echo -e "\n  ${BOLD}Storage group '${name}' — ${dc} disk(s):${NC}"
      while IFS= read -r disk; do
        local s
        s="$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')"
        printf "    %s  (%s)\n" "$disk" "$s"
      done < <(jsonc "$CONFIG_FILE" | jq -r ".storage_groups[$i].disks[]")
      pick_option "Choose topology for '${name}':" "${opts[@]}"
      _LAYOUT_IMPL_TOPOLOGIES["$name"]="$PICK_RESULT"
      info "Group '${name}': topology '${PICK_RESULT}' (selected)"
    fi
  done

  # ── Leftover OS disks (when topology=none and 2+ OS disks listed) ─────────
  if ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)); then
    local lc="${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]}"
    local opts=()
    while IFS= read -r line; do opts+=("$line"); done \
      < <(suggest_storage_topologies "$lc")
    echo -e "\n  ${BOLD}Leftover OS disks → dpool (${lc} disk(s)):${NC}"
    for d in "${_LAYOUT_IMPL_LEFTOVER_DISKS[@]}"; do
      local s
      s="$(lsblk -dno SIZE "$d" 2>/dev/null || echo '?')"
      printf "    %s  (%s)\n" "$d" "$s"
    done
    pick_option "Choose topology for leftover OS disks in dpool:" "${opts[@]}"
    _LAYOUT_IMPL_TOPOLOGIES["_leftover"]="$PICK_RESULT"
    info "Leftover disks topology: ${PICK_RESULT}"
  fi
}

# =============================================================================
# PARTITIONING
# =============================================================================

partition_os_disks_multi() {
  section "Partitioning OS Disk(s)"
  local esp_sz
  esp_sz="$(layout_resolve_esp_size)"
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
    wipefs -af "$disk"
    sgdisk --zap-all "$disk"
    # p1 — EFI System Partition
    sgdisk -n1:0:+"${esp_sz}" -t1:ef00 -c1:"EFI System" "$disk"
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
  # Publish layout state record (consumed by chroot.sh, finalize.sh).
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_ESP_PARTS=("${_LAYOUT_IMPL_ESP_PARTS[@]}")
}

partition_storage_disks_multi() {
  section "Partitioning Storage Disk(s)"

  # Config-defined storage groups
  local sg
  sg="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  local i
  for ((i = 0; i < sg; i++)); do
    local name
    name="$(cfg ".storage_groups[$i].name")"
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

create_multi_rpool() {
  section "Creating OS Pool (rpool)"
  build_enc_opts

  local pool_name
  pool_name="$(cfg '.os_pool.pool_name')"
  local ashift; ashift="$(install_config_os_pool_ashift)"

  local vdev_spec
  vdev_spec="$(build_vdev_spec "${_LAYOUT_IMPL_OS_TOPOLOGY}" \
    "${_LAYOUT_IMPL_ZFS_PARTS[@]}")"

  info "Pool: ${pool_name}  topology: ${_LAYOUT_IMPL_OS_TOPOLOGY}"
  info "vdev: ${vdev_spec}"

  # SC2086 (intentional): vdev_spec must be word-split into multiple args
  # for _zpool_create (e.g. "mirror /dev/sda1 /dev/sdb1" → 3 args). Built
  # from controlled inputs in build_vdev_spec, so word-splitting is safe.
  # shellcheck disable=SC2086
  _zpool_create "${pool_name}" "${ashift}" $vdev_spec
  _create_os_datasets "${pool_name}"
}

create_multi_dpool() {
  section "Creating Data Pool (dpool)"

  local sg
  sg="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  local has_left=false
  [[ -v "_LAYOUT_IMPL_STORAGE_PARTS[_leftover]" ]] && has_left=true

  if ((sg == 0)) && ! $has_left; then
    info "No storage groups and no leftover disks — skipping dpool."
    return
  fi
  build_enc_opts

  # Collect vdev specs from all groups
  local all_vdevs=()
  local i
  for ((i = 0; i < sg; i++)); do
    local name
    name="$(cfg ".storage_groups[$i].name")"
    local topo="${_LAYOUT_IMPL_TOPOLOGIES[$name]:-stripe}"
    local parts
    read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[$name]}"
    local vs
    vs="$(build_vdev_spec "$topo" "${parts[@]}")"
    # SC2206 (intentional): vs is a single string built from build_vdev_spec
    # output that we want word-split into separate vdev tokens (e.g.
    # "mirror /dev/sdb1 /dev/sdc1" → 3 array elements).
    # shellcheck disable=SC2206
    all_vdevs+=($vs)
    info "  Group '${name}': ${topo}  [${parts[*]}]"
  done

  if $has_left; then
    local topo="${_LAYOUT_IMPL_TOPOLOGIES[_leftover]:-independent}"
    local parts
    read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[_leftover]}"
    local vs
    vs="$(build_vdev_spec "$topo" "${parts[@]}")"
    # shellcheck disable=SC2206  # see comment in loop above
    all_vdevs+=($vs)
    info "  Group '_leftover': ${topo}  [${parts[*]}]"
  fi

  # Use the first storage group's ashift (all storage disks ideally match)
  local pashift; pashift="$(install_config_storage_group_ashift 0)"

  # SC2068 (intentional): all_vdevs holds pre-tokenised vdev spec elements
  # that must each become a separate argument to zpool create. Names are
  # internally generated so word-splitting is safe.
  # shellcheck disable=SC2068
  _zpool_create "dpool" "${pashift}" ${all_vdevs[@]}

  # ── Datasets ───────────────────────────────────────────────────────────────
  zfs create -o canmount=off -o mountpoint=none dpool/DATA

  # One dataset per config-defined group
  for ((i = 0; i < sg; i++)); do
    local name
    name="$(cfg ".storage_groups[$i].name")"
    local mnt
    mnt="$(cfg ".storage_groups[$i].mount")"
    local topo="${_LAYOUT_IMPL_TOPOLOGIES[$name]:-stripe}"

    if [[ "$topo" == "independent" ]]; then
      # Per-disk sub-datasets so each disk can be managed separately
      zfs create -o canmount=off -o mountpoint=none "dpool/DATA/${name}"
      local parts
      read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[$name]}"
      local j
      for j in "${!parts[@]}"; do
        zfs create \
          -o mountpoint="${mnt}/disk$((j + 1))" \
          "dpool/DATA/${name}/disk$((j + 1))"
        info "  dpool/DATA/${name}/disk$((j + 1)) → ${mnt}/disk$((j + 1))"
      done
    else
      zfs create -o mountpoint="${mnt}" "dpool/DATA/${name}"
      info "  dpool/DATA/${name} → ${mnt}"
    fi
  done

  # Dataset(s) for leftover OS disks
  if $has_left; then
    local topo="${_LAYOUT_IMPL_TOPOLOGIES[_leftover]:-independent}"
    if [[ "$topo" == "independent" ]]; then
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

mount_multi_esps() {
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
# LAYOUT INTERFACE (called by 03-install.sh)
# =============================================================================

layout_plan() {
  resolve_os_topology
  resolve_storage_topologies
  # Publish layout state record (consumed by chroot.sh, finalize.sh).
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_OS_POOL_NAME="$(cfg '.os_pool.pool_name')"
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_DATA_POOL_NAME=""
  local _sg_count
  _sg_count="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  if ((_sg_count > 0)) || ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)); then
    # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
    LAYOUT_DATA_POOL_NAME="dpool"
  fi
  _layout_verify_plan_contract
}
layout_partition() {
  partition_os_disks_multi
  partition_storage_disks_multi
  _layout_verify_partition_contract
}
layout_create_pools() { create_multi_rpool; create_multi_dpool; }
layout_mount_esp()    { mount_multi_esps; }
