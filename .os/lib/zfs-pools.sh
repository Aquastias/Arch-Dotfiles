#!/usr/bin/env bash
# =============================================================================
# lib/zfs-pools.sh — ZFS pool and dataset primitives
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   install_zfs_tools_if_needed  — fallback ZFS install if bootstrap was skipped
#   build_enc_opts               — populates ENC_OPTS array from config
#   _zpool_create                — creates a pool with standard Arch ZFS settings
#   _create_os_datasets          — creates ROOT/arch, home, var, tmp, swap zvol
#   build_storage_vdev_spec      — converts (topology, parts) → vdev spec string
#
# GLOBALS:
#   ENC_OPTS   — array of -O encryption flags for zpool create; set by build_enc_opts
# =============================================================================

ENC_OPTS=() # populated by build_enc_opts(); consumed by _zpool_create()

# =============================================================================
# FALLBACK ZFS INSTALL
# =============================================================================
# Runs only if the ZFS kernel module is not already loaded.
# This means 01-bootstrap-zfs.sh was not run — we handle it gracefully here.

install_zfs_tools_if_needed() {
  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded — skipping tool install."
    return
  fi

  section "Installing ZFS Tools (fallback — bootstrap was not run)"
  warn "ZFS is not loaded. It is strongly recommended to run 01-bootstrap-zfs.sh first."
  warn "Attempting fallback install now..."

  # Add archzfs repo if not already present
  # Note: archzfs.com is stale since Feb 2026. Use the GitHub repo.
  if ! grep -q '\[archzfs\]' /etc/pacman.conf; then
    local ARCHZFS_KEY="3A9917BF0DED5C13F69AC68FABEC0A1208037BE9"
    pacman-key --recv-keys "$ARCHZFS_KEY" 2>/dev/null ||
      pacman-key --keyserver hkps://keyserver.ubuntu.com \
        --recv-keys "$ARCHZFS_KEY"
    pacman-key --lsign-key "$ARCHZFS_KEY"
    printf '\n[archzfs]\nSigLevel = Never\nServer = https://github.com/archzfs/archzfs/releases/download/experimental\n' \
      >>/etc/pacman.conf
    pacman -Sy --noconfirm
  fi

  # Try pre-built first (~80 MB), fall back to DKMS build (~900 MB)
  pacman -S --noconfirm --needed zfs-linux zfs-utils 2>/dev/null || {
    warn "No pre-built module available. DKMS build will start (5–30 min)..."
    local headers_pkg="linux-headers"
    uname -r | grep -q 'lts' && headers_pkg="linux-lts-headers"
    pacman -S --noconfirm --needed "${headers_pkg}" dkms zfs-dkms zfs-utils ||
      error "ZFS DKMS install failed. Check network and archzfs availability."
  }

  modprobe zfs || error "Failed to load ZFS kernel module after install."
  [[ -f /etc/hostid ]] || zgenhostid
  info "ZFS installed. hostid: $(hostid)"
}

# =============================================================================
# ENCRYPTION OPTIONS
# =============================================================================

build_enc_opts() {
  # Reads encryption setting from config and populates the ENC_OPTS global.
  # ENC_OPTS is appended to every zpool create call via "${ENC_OPTS[@]}".
  ENC_OPTS=()
  local enc
  enc="$(cfgo '.options.encryption')"
  enc="${enc:-false}"
  if [[ "$enc" == "true" ]]; then
    warn "Encryption enabled — you will be prompted for a passphrase now."
    warn "This same passphrase is required at every boot (entered at the console)."
    ENC_OPTS=(
      -O encryption=aes-256-gcm
      -O keyformat=passphrase
      -O keylocation=prompt
    )
  fi
}

# =============================================================================
# POOL CREATION HELPER
# =============================================================================

_zpool_create() {
  # Creates a ZFS pool with standard Arch Linux settings.
  #
  # Usage: _zpool_create <pool_name> <ashift> <vdev_spec...>
  #   pool_name   — e.g. rpool, dpool
  #   ashift      — 12 (4K, SATA) or 13 (8K, NVMe)
  #   vdev_spec   — e.g. "mirror /dev/sda1 /dev/sdb1" or "/dev/nvme0n1p2"
  #
  # Pool-level options (-o):
  #   ashift      — physical sector size hint (critical for alignment)
  #   autotrim    — enables automatic TRIM for SSDs/NVMe
  #
  # Dataset-level options (-O, inherited by all datasets in pool):
  #   acltype=posixacl  — required for correct Linux ACL support
  #   xattr=sa          — stores xattrs in inodes (faster than separate files)
  #   dnodesize=auto    — allows larger dnodes for xattr-heavy workloads
  #   compression=lz4   — transparent compression; near-zero CPU cost, saves ~20–40%
  #   normalization=formD — Unicode normalization for filename compatibility
  #   relatime=on       — atime only updated if mtime or ctime also changed (performance)
  #   canmount=off      — pool root dataset should not be auto-mounted
  #   mountpoint=none   — no default mountpoint; individual datasets set their own

  local pool_name="$1" ashift="$2"
  shift 2
  local vdev_spec="$*"

  # shellcheck disable=SC2086
  zpool create -f \
    -o ashift="${ashift}" \
    -o autotrim=on \
    -O acltype=posixacl \
    -O xattr=sa \
    -O dnodesize=auto \
    -O compression=lz4 \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off \
    -O mountpoint=none \
    "${ENC_OPTS[@]}" \
    -R "${MOUNT_ROOT}" \
    "${pool_name}" \
    $vdev_spec

  info "Pool '${pool_name}' created (ashift=${ashift})."
}

# =============================================================================
# OS DATASET CREATION (shared between single-disk and multi-disk modes)
# =============================================================================

_create_os_datasets() {
  # Creates the standard Arch Linux ZFS dataset hierarchy inside pool_name.
  # Called once for rpool in both single and multi mode.
  #
  # Dataset layout:
  #   <pool>/ROOT              — container (canmount=off)
  #   <pool>/ROOT/arch         — actual root filesystem (mountpoint=/)
  #   <pool>/home              — user home directories
  #   <pool>/var               — system state (atime=off for performance)
  #   <pool>/var/log           — separate so log rotation can't fill root
  #   <pool>/var/cache         — separate so package cache can be cleared safely
  #   <pool>/tmp               — tmpfs-like (sync=off, no setuid/exec)
  #   <pool>/swap              — swap zvol (if enabled)

  local pool_name="$1"
  section "Creating OS Datasets (${pool_name})"

  local swap_on
  swap_on="$(cfgo '.options.swap')"
  swap_on="${swap_on:-true}"
  local cfg_swap_sz
  cfg_swap_sz="$(cfgo '.options.swap_size')"
  local swap_arg
  if [[ -z "$cfg_swap_sz" || "$cfg_swap_sz" == "auto" ]]; then
    # auto = RAM × 2, which accommodates hibernation (suspend-to-disk)
    swap_arg="$(($(ram_gib) * 2))G"
    info "Swap size: ${swap_arg}  (RAM × 2, auto)"
  else
    swap_arg="$cfg_swap_sz"
    info "Swap size: ${swap_arg}  (from config)"
  fi

  # ROOT container — not directly mountable
  zfs create -o canmount=off -o mountpoint=none "${pool_name}/ROOT"

  # The actual root filesystem — canmount=noauto so the installer mounts it
  # explicitly, but the boot system (zfs-mount-generator) handles it on reboot
  zfs create -o canmount=noauto -o mountpoint=/ "${pool_name}/ROOT/arch"
  zpool set bootfs="${pool_name}/ROOT/arch" "${pool_name}"
  zfs mount "${pool_name}/ROOT/arch"

  zfs create -o mountpoint=/home "${pool_name}/home"
  zfs create -o mountpoint=/var -o atime=off "${pool_name}/var"
  zfs create -o mountpoint=/var/log "${pool_name}/var/log"
  zfs create -o mountpoint=/var/cache "${pool_name}/var/cache"

  # /tmp: sync=disabled (writes go to RAM first, flushed periodically)
  #       setuid=off and exec=off harden against privilege escalation via /tmp
  zfs create \
    -o mountpoint=/tmp \
    -o sync=disabled \
    -o setuid=off \
    -o exec=off \
    "${pool_name}/tmp"
  chmod 1777 "${MOUNT_ROOT}/tmp"

  if [[ "$swap_on" == "true" ]]; then
    info "Creating swap zvol: ${swap_arg}"
    # ZFS swap zvol best practices:
    #   volblocksize = page size   — aligns with kernel memory pages
    #   compression=zle           — zero-suppression; good for sparse swap pages
    #   logbias=throughput        — sequential writes preferred
    #   sync=always               — data integrity required for swap
    #   primarycache=metadata     — don't cache swap data in ARC (wastes RAM)
    #   secondarycache=none       — don't use L2ARC for swap
    #   com.sun:auto-snapshot=false — never snapshot the swap zvol
    zfs create \
      -V "${swap_arg}" \
      -b "$(getconf PAGESIZE)" \
      -o compression=zle \
      -o logbias=throughput \
      -o sync=always \
      -o primarycache=metadata \
      -o secondarycache=none \
      -o com.sun:auto-snapshot=false \
      "${pool_name}/swap"
    mkswap -f "/dev/zvol/${pool_name}/swap"
  fi

  info "OS datasets created under '${pool_name}'."
}

# =============================================================================
# STORAGE VDEV SPEC BUILDER
# =============================================================================

build_storage_vdev_spec() {
  # Converts a topology name and a list of partition paths into a zpool
  # vdev specification string suitable for passing to zpool create.
  #
  # Usage: build_storage_vdev_spec <topology> <part1> [part2] ...
  # Outputs: the vdev spec string (echoed to stdout)
  #
  # Topologies:
  #   mirror      — "mirror part1 part2 ..."  (all disks mirrored)
  #   stripe      — "part1 part2 ..."          (striped, no redundancy)
  #   raidz1      — "raidz1 part1 part2 ..."  (1 parity disk)
  #   raidz2      — "raidz2 part1 part2 ..."  (2 parity disks)
  #   independent — "part1 part2 ..."          (each disk its own vdev;
  #                                             same as stripe at pool level
  #                                             but datasets are per-disk)

  local topo="$1"
  shift
  local parts=("$@")
  case "$topo" in
  mirror) echo "mirror ${parts[*]}" ;;
  stripe) echo "${parts[*]}" ;;
  raidz1) echo "raidz1 ${parts[*]}" ;;
  raidz2) echo "raidz2 ${parts[*]}" ;;
  independent) echo "${parts[*]}" ;;
  *) error "Unknown storage topology: '$topo'" ;;
  esac
}
