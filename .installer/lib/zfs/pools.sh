#!/usr/bin/env bash
# =============================================================================
# lib/zfs/pools.sh — ZFS pool and dataset primitives
# =============================================================================
# Used by: 03-install.sh, lib/layout/zfs/*.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   zfs_install_tools_if_needed — fallback ZFS install if bootstrap was skipped
#   zfs_ram_gib                 — installed RAM in whole GiB
#   zfs_create_pool             — a pool with standard Arch ZFS settings
#   zfs_create_os_datasets      — ROOT/arch, home, var, tmp, swap zvol
#   zfs_vdev_spec               — (topology, parts) → vdev spec string
#                                 (lib/zfs/vdev-spec.sh, sourced below)
#   zfs_valid_pool_name, zfs_data_pool_topology_ok,
#   zfs_redundant_size_mismatch — layout validation helpers
# Encryption (zfs_collect_encryption_passphrase, zfs_encryption_options) lives
# in lib/zfs/encryption.sh, sourced below.
# =============================================================================

# Rollback Dataset list + early-create helper (impermanence). Guard-source so
# re-sourcing (validation.sh also pulls it in) is a harmless no-op.
if ! declare -p ROLLBACK_DATASETS >/dev/null 2>&1; then
  # shellcheck source=../impermanence-common.sh
  source "${BASH_SOURCE[0]%/*}/../impermanence-common.sh"
fi

# Shared confirmed-secret reader used by zfs_collect_encryption_passphrase.
# shellcheck source=../prompt.sh
declare -F prompt_secret >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../prompt.sh"

# The encryption passphrase + pool options (ZFS_ENCRYPTION_OPTIONS,
# ZFS_PASSPHRASE); re-sourcing resets both, as before the split.
# shellcheck source=./encryption.sh
source "${BASH_SOURCE[0]%/*}/encryption.sh"
# shellcheck source=vdev-spec.sh
source "${BASH_SOURCE[0]%/*}/vdev-spec.sh"

# =============================================================================
# FALLBACK ZFS INSTALL
# =============================================================================
# Runs only if the ZFS kernel module is not currently loaded — e.g. because
# 01-bootstrap-zfs.sh was skipped, or its build did not leave a loaded module.
# We recover here using the SAME shared logic bootstrap uses (lib/zfs/module.sh),
# so this path can never drift into the old bug where it pulled the wrong
# kernel's headers and DKMS built a module modprobe could not find (ADR 0023).

zfs_install_tools_if_needed() {
  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded — skipping tool install."
    return
  fi

  section "Installing ZFS Tools (ZFS module not loaded — fallback)"
  warn "ZFS kernel module is not loaded." \
       "01-bootstrap-zfs.sh normally loads it; running the fallback now."

  local kernel_version
  kernel_version="$(uname -r)"

  # Ensure the archzfs repo + signing key are present (idempotent — no-op if
  # bootstrap already added them).
  zfs_add_archzfs_repo

  # Always DKMS on the live ISO, built against the EXACT running kernel using
  # the ISO's own headers — never an unpinned `pacman -S linux-headers`, which
  # would grab a newer kernel's headers and break the build.
  zfs_install_dkms "$kernel_version"
  zfs_load_module

  [[ -f /etc/hostid ]] || zgenhostid
  info "ZFS installed. hostid: $(hostid)"
}

# =============================================================================
# RAM DETECTION (shared between layout modules)
# =============================================================================

zfs_ram_gib() {
  # Returns total installed RAM in whole GiB (rounded up).
  local kib
  kib="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  echo $(((kib + 1048575) / 1048576))
}

# =============================================================================
# STABLE DEVICE PATHS (multi-disk reorder safety)
# =============================================================================
# Pools must be created with /dev/disk/by-id paths, never bare /dev/sdX. ZFS
# records the path it was given in the vdev label AND in zpool.cache; on a
# multi-disk machine the kernel's disk-enumeration order changes across reboots,
# so a cached /dev/sdb1 points at a DIFFERENT disk at boot. The root pool
# survives (the initramfs imports it by scanning /dev/disk/by-id via
# zfs_import_dir), but data pools imported from the cache fail with
# "one or more devices is currently unavailable". by-id names are stable, so
# translating here fixes both the initramfs late-hook import and the post-boot
# zfs-import-cache.service. (ADR 0028.)

_pools_directory_matches() {
  # Prints the symlink in <dir> that resolves to <target>, or empty if none.
  # Prefers a non-wwn id (ata-/nvme-/scsi-/partuuid), else a wwn-, each chosen
  # lexicographically for a deterministic result.
  local directory="$1" target="$2" link pref="" wwn=""
  [[ -d "$directory" ]] || return 0
  for link in "$directory"/*; do
    [[ -e "$link" ]] || continue
    [[ "$(readlink -f "$link" 2>/dev/null)" == "$target" ]] || continue
    case "${link##*/}" in
    wwn-*) [[ -z "$wwn" || "$link" < "$wwn" ]] && wwn="$link" ;;
    *) [[ -z "$pref" || "$link" < "$pref" ]] && pref="$link" ;;
    esac
  done
  printf '%s' "${pref:-$wwn}"
}

_pools_stable_partition_path() {
  # Resolves a partition device path to a stable symlink that points at the
  # same node, so the pool label + zpool.cache survive /dev/sdX reordering.
  # Tier 1: /dev/disk/by-id (matches the repo's zfs_import_dir convention).
  # Tier 2: /dev/disk/by-partuuid (always present for GPT partitions, fully
  # stable — covers disks/VMs that expose no usable by-id). Falls back to the
  # input unchanged when nothing maps to it (loop/zram, or a bare test host).
  # ZFS_BYID_DIR / ZFS_BYPARTUUID_DIR override the dirs for tests.
  local part="$1"
  local target
  target="$(readlink -f "$part" 2>/dev/null)"
  [[ -n "$target" ]] || { printf '%s' "$part"; return; }
  local found
  found="$(_pools_directory_matches "${ZFS_BYID_DIR:-/dev/disk/by-id}" \
    "$target")"
  [[ -n "$found" ]] && { printf '%s' "$found"; return; }
  found="$(_pools_directory_matches \
    "${ZFS_BYPARTUUID_DIR:-/dev/disk/by-partuuid}" "$target")"
  [[ -n "$found" ]] && { printf '%s' "$found"; return; }
  printf '%s' "$part"
}

_pools_translate_vdev() {
  # Echoes a vdev spec with each device token mapped to its stable by-id path;
  # topology keywords (mirror/raidz.../log/cache/...) pass through untouched.
  local out=() token
  for token in "$@"; do
    case "$token" in
    mirror | raidz | raidz1 | raidz2 | raidz3 | draid | draid[0-9]* \
      | spare | log | cache | special | dedup | stripe)
      out+=("$token") ;;
    *) out+=("$(_pools_stable_partition_path "$token")") ;;
    esac
  done
  printf '%s' "${out[*]}"
}

# =============================================================================
# POOL CREATION HELPER
# =============================================================================

# True when the given encryption opts read the key from an interactive prompt
# (keylocation=prompt). zfs_create_pool pipes the boot passphrase via stdin ONLY
# then — the root pool (prompt) gets it; a keyfile-on-root data pool
# (keylocation=file://…, ADR 0043) does not, so there is no second prompt. Empty
# opts (a plaintext pool) are not a prompt. Pure: scans its arguments.
_pools_prompt_encryption_options() {
  [[ " $* " == *" keylocation=prompt "* ]]
}

# zfs_create_pool <pool_name> <ashift> <vdev_spec...> — a ZFS pool with
# standard Arch Linux settings.
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
#   compression=lz4 — transparent compression; near-zero CPU cost,
#                     saves ~20–40%
#   normalization=formD — Unicode normalization for filename compatibility
#   relatime=on     — atime only updated if mtime or ctime also
#                     changed (performance)
#   canmount=off      — pool root dataset should not be auto-mounted
#   mountpoint=none — no default mountpoint; individual datasets
#                     set their own
zfs_create_pool() {
  local pool_name="$1" ashift="$2"
  shift 2
  local vdev_spec="$*"

  # Map bare /dev/sdX device tokens to stable /dev/disk/by-id paths so the pool
  # label + zpool.cache survive disk-enumeration reordering across reboots
  # (ADR 0028). Settle udev first so the freshly-created -partN by-id symlinks
  # exist. SC2086 (intentional): word-split the controlled vdev_spec into tokens.
  command_exists udevadm && udevadm settle 2>/dev/null || true
  # shellcheck disable=SC2086
  vdev_spec="$(_pools_translate_vdev $vdev_spec)"

  local -a create_options=(
    -f
    -o ashift="${ashift}"
    -o autotrim=on
    -O acltype=posixacl
    -O xattr=sa
    -O dnodesize=auto
    -O compression=lz4
    -O normalization=formD
    -O relatime=on
    -O canmount=off
    -O mountpoint=none
    "${ZFS_ENCRYPTION_OPTIONS[@]}"
    -R "${MOUNT_ROOT}"
    "${pool_name}"
  )
  # SC2086 (intentional): vdev_spec must be word-split into multiple args
  # (e.g. "mirror /dev/sda1 /dev/sdb1" → 3 args to zpool create). It is built
  # by zfs_vdev_spec() from controlled inputs (topology + partition paths)
  # so word-splitting is the desired behaviour here.
  if _pools_prompt_encryption_options "${ZFS_ENCRYPTION_OPTIONS[@]}"; then
    # Pipe the passphrase via stdin — zpool create reads it once when
    # keylocation=prompt is set. printf ensures no trailing newline issues. A
    # keyfile-on-root data pool (keylocation=file://…) is NOT piped — it loads
    # its key from the file, so the operator never types a second secret.
    # shellcheck disable=SC2086
    printf '%s\n' "$ZFS_PASSPHRASE" \
      | zpool create "${create_options[@]}" $vdev_spec
  else
    # shellcheck disable=SC2086
    zpool create "${create_options[@]}" $vdev_spec
  fi

  info "Pool '${pool_name}' created (ashift=${ashift})."
}

# =============================================================================
# OS DATASET CREATION (shared between single-disk and multi-disk modes)
# =============================================================================

# zfs_create_os_datasets <pool_name> — the standard Arch Linux ZFS dataset
# hierarchy inside pool_name. Called once for rpool in both single and multi
# mode.
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
# zfs_auto_swap_gib <ram_gib> <pool_bytes> — the auto swap zvol size in GiB:
# RAM × 2, capped to a quarter of the pool, never below 2.
zfs_auto_swap_gib() {
  local ram_gib="$1" pool_bytes="$2" swap_gib cap_gib
  swap_gib=$((ram_gib * 2))
  cap_gib=$((pool_bytes / 1024 / 1024 / 1024 / 4))
  ((cap_gib < 2)) && cap_gib=2
  ((swap_gib > cap_gib)) && swap_gib=$cap_gib
  printf '%s\n' "$swap_gib"
}

# _pools_pool_size_bytes <pool> — the pool's size in bytes (0 if unknown).
_pools_pool_size_bytes() {
  zpool list -Hp -o size "$1" 2>/dev/null | awk 'NR == 1 { print $1 + 0 }'
}

zfs_create_os_datasets() {
  local pool_name="$1"
  section "Creating OS Datasets (${pool_name})"

  local swap_on configured_swap_size swap_size
  swap_on="$(install_config_swap_enabled)"
  configured_swap_size="$(config_optional '.options.swap_size')"
  if [[ -z "$configured_swap_size" || "$configured_swap_size" == "auto" ]]; then
    # auto = RAM × 2 (accommodates hibernation), capped to a quarter of the
    # pool so a big-RAM box on a small disk still fits its rpool.
    swap_size="$(zfs_auto_swap_gib "$(zfs_ram_gib)" \
      "$(_pools_pool_size_bytes "$pool_name")")G"
    info "Swap size: ${swap_size}  (RAM × 2, capped to pool/4, auto)"
  else
    swap_size="$configured_swap_size"
    info "Swap size: ${swap_size}  (from config)"
  fi

  _pools_create_root_hierarchy "$pool_name"
  _pools_create_impermanence_datasets "$pool_name"
  if [[ "$swap_on" == "true" ]]; then
    _pools_create_swap_zvol "$pool_name" "$swap_size"
  fi

  info "OS datasets created under '${pool_name}'."
}

_pools_create_root_hierarchy() {
  local pool_name="$1"
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
}

# Impermanence: create the Rollback Datasets now — before pacstrap — so the OS
# install writes /etc, /root, … onto them (canmount=on → auto-mounted under
# MOUNT_ROOT) and they land in the zfs-list.cache built during chroot config.
# Creating them later (in the chroot module) leaves them noauto + uncached, so
# they never mount and the @blank rollback is a no-op. No-op when disabled.
_pools_create_impermanence_datasets() {
  local pool_name="$1"
  [[ "$(install_config_impermanence_enabled)" == "true" ]] || return 0
  info "Impermanence enabled — creating Persist + Rollback Datasets on" \
       "${pool_name}."
  impermanence_common_create_persist_dataset \
    "$(install_config_impermanence_dataset)" \
    "$(install_config_impermanence_mount)"
  impermanence_common_create_rollback_datasets "${pool_name}"
}

# ZFS swap zvol best practices:
#   volblocksize = page size   — aligns with kernel memory pages
#   compression=zle           — zero-suppression; good for sparse swap pages
#   logbias=throughput        — sequential writes preferred
#   sync=always               — data integrity required for swap
#   primarycache=metadata     — don't cache swap data in ARC (wastes RAM)
#   secondarycache=none       — don't use L2ARC for swap
#   com.sun:auto-snapshot=false — never snapshot the swap zvol
_pools_create_swap_zvol() {
  local pool_name="$1" swap_size="$2"
  info "Creating swap zvol: ${swap_size}"
  zfs create \
    -V "${swap_size}" \
    -b "$(getconf PAGESIZE)" \
    -o compression=zle \
    -o logbias=throughput \
    -o sync=always \
    -o primarycache=metadata \
    -o secondarycache=none \
    -o com.sun:auto-snapshot=false \
    "${pool_name}/swap"
  mkswap -f "/dev/zvol/${pool_name}/swap"
}

# =============================================================================
# STANDALONE DATA POOL TOPOLOGY VALIDATION (ADR 0027)
# =============================================================================

_pools_validate_topology() {
  # Pure check for a Standalone Data Pool's topology against its disk count.
  # Silent + returns 0 when valid; prints a reason + returns 1 when invalid.
  #
  # Usage: _pools_validate_topology <topology> <disk_count>
  #
  # 'none' and 'independent' are rejected: zfs_vdev_spec maps 'none' to the
  # first disk only (silently dropping the rest), and 'independent' has no
  # meaning for a single standalone pool. Operators are pointed to 'stripe'
  # (one non-redundant pool) or multiple data_pools[] entries (separate pools).
  local topology="$1" count="$2" min
  case "$topology" in
  none | independent)
    printf '%s' "topology '${topology}' is not valid for a standalone data" \
      " pool; use 'stripe' for one non-redundant pool, or multiple" \
      " data_pools[] entries for separate pools"
    return 1
    ;;
  stripe) min=1 ;;
  mirror) min=2 ;;
  raidz | raidz1) min=2 ;;
  raidz2) min=3 ;;
  *)
    printf '%s' "unknown topology '${topology}'"
    return 1
    ;;
  esac
  if ((count < min)); then
    printf '%s' "topology '${topology}' needs at least ${min} disk(s), got" \
      " ${count}"
    return 1
  fi
  return 0
}

# Filesystem-aware Standalone Data Pool topology check (ADR 0043). A zfs pool
# runs the native vdev validator (_pools_validate_topology); a non-zfs pool
# (btrfs/ext4/xfs) carries a native topology the zfs validator doesn't know
# (e.g. btrfs raid1), and its validity was already gated by validation.sh's
# _validation_topology_for_filesystem — so it passes here. Silent + 0 when ok;
# prints a reason + returns 1 on a zfs mismatch. Pure.
zfs_data_pool_topology_ok() {
  local filesystem="$1" topology="$2" count="$3"
  [[ "$filesystem" == "zfs" ]] || return 0
  _pools_validate_topology "$topology" "$count"
}

zfs_valid_pool_name() {
  # Pure check for a Standalone Data Pool name (the literal zpool name).
  # Silent + returns 0 when valid; prints a reason + returns 1 when not.
  # Rejects what `zpool create` would choke on: bad characters / leading
  # digit, a 'cN' prefix (looks like a Solaris device), and reserved ZFS
  # vdev words. (Not retrofitted onto os_pool_name/storage_pool_name.)
  local name="$1"
  if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    printf '%s' "name '${name}' must match ^[A-Za-z][A-Za-z0-9_-]*\$"
    return 1
  fi
  if [[ "$name" =~ ^c[0-9] ]]; then
    printf '%s' "name '${name}' cannot start with cN (looks like a device)"
    return 1
  fi
  case "$name" in
  mirror | raidz | raidz1 | raidz2 | raidz3 | draid | draid[0-9]* \
    | spare | log | cache | special | dedup)
    printf '%s' "name '${name}' is a reserved ZFS word"
    return 1
    ;;
  esac
  return 0
}

zfs_redundant_size_mismatch() {
  # Pure decision: returns 0 (warn) when a redundant topology spans disks of
  # differing sizes — ZFS caps usable space to the smallest member. Returns
  # 1 (no warn) for stripe, a single disk, or equal-size redundant disks.
  #
  # Usage: zfs_redundant_size_mismatch <topology> <size1> [size2] ...
  local topology="$1"
  shift
  local sizes=("$@")
  case "$topology" in
  mirror | raidz1 | raidz2 | raidz3) ;;
  *) return 1 ;; # stripe / none / independent / unknown — never warn
  esac
  ((${#sizes[@]} >= 2)) || return 1
  local first="${sizes[0]}" size
  for size in "${sizes[@]}"; do
    [[ "$size" != "$first" ]] && return 0
  done
  return 1
}
