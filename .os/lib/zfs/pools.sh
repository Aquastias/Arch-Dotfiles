#!/usr/bin/env bash
# =============================================================================
# lib/zfs/pools.sh — ZFS pool and dataset primitives
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   install_zfs_tools_if_needed  — fallback ZFS install if bootstrap was skipped
#   build_enc_opts               — populates ENC_OPTS array from config
#   _zpool_create — creates a pool with standard Arch ZFS settings
#   _create_os_datasets          — creates ROOT/arch, home, var, tmp, swap zvol
#   build_vdev_spec              — converts (topology, parts) → vdev spec string
#
# GLOBALS:
#   ENC_OPTS — array of -O encryption flags for zpool create;
#                set by build_enc_opts
# =============================================================================

ENC_OPTS=() # populated by build_enc_opts(); consumed by _zpool_create()

# Rollback Dataset list + early-create helper (impermanence). Guard-source so
# re-sourcing (validation.sh also pulls it in) is a harmless no-op.
if ! declare -p ROLLBACK_DATASETS >/dev/null 2>&1; then
  # shellcheck source=../impermanence-common.sh
  source "${BASH_SOURCE[0]%/*}/../impermanence-common.sh"
fi

# Shared confirmed-secret reader used by collect_enc_passphrase.
# shellcheck source=../prompt.sh
[[ "$(type -t prompt_secret)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../prompt.sh"

# =============================================================================
# FALLBACK ZFS INSTALL
# =============================================================================
# Runs only if the ZFS kernel module is not currently loaded — e.g. because
# 01-bootstrap-zfs.sh was skipped, or its build did not leave a loaded module.
# We recover here using the SAME shared logic bootstrap uses (lib/zfs/module.sh),
# so this path can never drift into the old bug where it pulled the wrong
# kernel's headers and DKMS built a module modprobe could not find (ADR 0023).

install_zfs_tools_if_needed() {
  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded — skipping tool install."
    return
  fi

  section "Installing ZFS Tools (ZFS module not loaded — fallback)"
  warn "ZFS kernel module is not loaded." \
       "01-bootstrap-zfs.sh normally loads it; running the fallback now."

  local kver
  kver="$(uname -r)"

  # Ensure the archzfs repo + signing key are present (idempotent — no-op if
  # bootstrap already added them).
  zfs_add_archzfs_repo

  # Always DKMS on the live ISO, built against the EXACT running kernel using
  # the ISO's own headers — never an unpinned `pacman -S linux-headers`, which
  # would grab a newer kernel's headers and break the build.
  zfs_install_dkms "$kver"
  zfs_load_module

  [[ -f /etc/hostid ]] || zgenhostid
  info "ZFS installed. hostid: $(hostid)"
}

# =============================================================================
# RAM DETECTION (shared between layout modules)
# =============================================================================

ram_gib() {
  # Returns total installed RAM in whole GiB (rounded up).
  local kib
  kib="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  echo $(((kib + 1048575) / 1048576))
}

# =============================================================================
# ENCRYPTION OPTIONS
# =============================================================================

# Global passphrase storage — set by collect_enc_passphrase(),
# used by _zpool_create()
ZFS_PASSPHRASE=""

collect_enc_passphrase() {
  # Prompts for the ZFS encryption passphrase with confirmation before any
  # pool creation. Reads from /dev/tty so it works regardless of stdin state.
  # Sets the global ZFS_PASSPHRASE used by _zpool_create via stdin pipe.
  local enc; enc="$(install_config_encryption_enabled)"
  [[ "$enc" == "true" ]] || return 0

  # Non-interactive seam (VM/test harness only): a preset passphrase skips the
  # /dev/tty prompt so an encrypted install runs unattended. Operator installs
  # leave INSTALL_ENC_PASSPHRASE unset and are prompted as before. ZFS itself
  # still enforces the ≥8-char rule at pool creation.
  if [[ -n "${INSTALL_ENC_PASSPHRASE:-}" ]]; then
    ZFS_PASSPHRASE="$INSTALL_ENC_PASSPHRASE"
    info "ZFS encryption passphrase taken from INSTALL_ENC_PASSPHRASE (preset)."
    return 0
  fi

  section "ZFS Encryption Passphrase"
  warn "Encryption is enabled. ALL data on the pools will be encrypted."
  warn "This passphrase is required at EVERY boot." \
       "Losing it means losing all data."
  echo ""

  # Shared confirmed-secret reader (lib/prompt.sh). ZFS enforces ≥8 at pool
  # creation; we pre-check here for a friendlier retry.
  prompt_secret ZFS_PASSPHRASE "ZFS passphrase" 8
  info "Passphrase set. It will be applied to all encrypted pools."
}

build_enc_opts() {
  # Populates ENC_OPTS global from config.
  # The passphrase is NOT set here — it must be collected via
  # collect_enc_passphrase() before pool creation, then piped via stdin.
  ENC_OPTS=()
  local enc; enc="$(install_config_encryption_enabled)"
  if [[ "$enc" == "true" ]]; then
    # keylocation=prompt means zpool create reads the passphrase from stdin.
    # We pipe ZFS_PASSPHRASE to it in _zpool_create() below.
    ENC_OPTS=(
      -O encryption=aes-256-gcm
      -O keyformat=passphrase
      -O keylocation=prompt
    )
  fi
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

_zfs_dir_match() {
  # Prints the symlink in <dir> that resolves to <target>, or empty if none.
  # Prefers a non-wwn id (ata-/nvme-/scsi-/partuuid), else a wwn-, each chosen
  # lexicographically for a deterministic result.
  local dir="$1" target="$2" link pref="" wwn=""
  [[ -d "$dir" ]] || return 0
  for link in "$dir"/*; do
    [[ -e "$link" ]] || continue
    [[ "$(readlink -f "$link" 2>/dev/null)" == "$target" ]] || continue
    case "${link##*/}" in
    wwn-*) [[ -z "$wwn" || "$link" < "$wwn" ]] && wwn="$link" ;;
    *) [[ -z "$pref" || "$link" < "$pref" ]] && pref="$link" ;;
    esac
  done
  printf '%s' "${pref:-$wwn}"
}

_zfs_stable_part_path() {
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
  found="$(_zfs_dir_match "${ZFS_BYID_DIR:-/dev/disk/by-id}" "$target")"
  [[ -n "$found" ]] && { printf '%s' "$found"; return; }
  found="$(_zfs_dir_match \
    "${ZFS_BYPARTUUID_DIR:-/dev/disk/by-partuuid}" "$target")"
  [[ -n "$found" ]] && { printf '%s' "$found"; return; }
  printf '%s' "$part"
}

_zpool_translate_vdev() {
  # Echoes a vdev spec with each device token mapped to its stable by-id path;
  # topology keywords (mirror/raidz.../log/cache/...) pass through untouched.
  local out=() tok
  for tok in "$@"; do
    case "$tok" in
    mirror | raidz | raidz1 | raidz2 | raidz3 | draid | draid[0-9]* \
      | spare | log | cache | special | dedup | stripe)
      out+=("$tok") ;;
    *) out+=("$(_zfs_stable_part_path "$tok")") ;;
    esac
  done
  printf '%s' "${out[*]}"
}

# =============================================================================
# POOL CREATION HELPER
# =============================================================================

# True when the given encryption opts read the key from an interactive prompt
# (keylocation=prompt). _zpool_create pipes the boot passphrase via stdin ONLY
# then — the root pool (prompt) gets it; a keyfile-on-root data pool
# (keylocation=file://…, ADR 0043) does not, so there is no second prompt. Empty
# opts (a plaintext pool) are not a prompt. Pure: scans its arguments.
_enc_opts_prompt() {
  [[ " $* " == *" keylocation=prompt "* ]]
}

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
  #   compression=lz4 — transparent compression; near-zero CPU cost,
  #                     saves ~20–40%
  #   normalization=formD — Unicode normalization for filename compatibility
  #   relatime=on     — atime only updated if mtime or ctime also
  #                     changed (performance)
  #   canmount=off      — pool root dataset should not be auto-mounted
  #   mountpoint=none — no default mountpoint; individual datasets
  #                     set their own

  local pool_name="$1" ashift="$2"
  shift 2
  local vdev_spec="$*"

  # Map bare /dev/sdX device tokens to stable /dev/disk/by-id paths so the pool
  # label + zpool.cache survive disk-enumeration reordering across reboots
  # (ADR 0028). Settle udev first so the freshly-created -partN by-id symlinks
  # exist. SC2086 (intentional): word-split the controlled vdev_spec into tokens.
  command -v udevadm >/dev/null 2>&1 && udevadm settle 2>/dev/null || true
  # shellcheck disable=SC2086
  vdev_spec="$(_zpool_translate_vdev $vdev_spec)"

  # SC2086 (intentional): vdev_spec must be word-split into multiple args
  # (e.g. "mirror /dev/sda1 /dev/sdb1" → 3 args to zpool create). It is built
  # by build_vdev_spec() from controlled inputs (topology + partition paths)
  # so word-splitting is the desired behaviour here.
  if _enc_opts_prompt "${ENC_OPTS[@]}"; then
    # Pipe the passphrase via stdin — zpool create reads it once when
    # keylocation=prompt is set. printf ensures no trailing newline issues. A
    # keyfile-on-root data pool (keylocation=file://…) is NOT piped — it loads
    # its key from the file, so the operator never types a second secret.
    # shellcheck disable=SC2086
    printf '%s\n' "$ZFS_PASSPHRASE" | zpool create -f \
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
  else
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
  fi

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
  swap_on="$(install_config_swap_enabled)"
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

  # Impermanence: create the Rollback Datasets now — before pacstrap — so the OS
  # install writes /etc, /root, … onto them (canmount=on → auto-mounted under
  # MOUNT_ROOT) and they land in the zfs-list.cache built during chroot config.
  # Creating them later (in the chroot module) leaves them noauto + uncached, so
  # they never mount and the @blank rollback is a no-op. No-op when disabled.
  if [[ "$(install_config_impermanence_enabled)" == "true" ]]; then
    info "Impermanence enabled — creating Persist + Rollback Datasets on ${pool_name}."
    imp_create_persist_dataset "$(install_config_impermanence_dataset)" \
                               "$(install_config_impermanence_mount)"
    imp_create_rollback_datasets "${pool_name}"
  fi

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

build_vdev_spec() {
  # Converts a topology name and a list of partition paths into a zpool
  # vdev specification string suitable for passing to zpool create.
  #
  # Usage: build_vdev_spec <topology> <part1> [part2] ...
  # Outputs: the vdev spec string (echoed to stdout)
  #
  # Topologies:
  #   mirror      — "mirror part1 part2 ..."  (all disks mirrored)
  #   stripe      — "part1 part2 ..."          (striped, no redundancy)
  #   none        — "part1"                    (single disk, first only)
  #   raidz1      — "raidz1 part1 part2 ..."  (1 parity disk)
  #   raidz2      — "raidz2 part1 part2 ..."  (2 parity disks)
  #   independent — "part1 part2 ..."          (each disk its own vdev;
  #                                             same as stripe at pool level
  #                                             but datasets are per-disk)

  local topo="$1"
  shift
  local parts=("$@")
  case "$topo" in
  mirror)      echo "mirror ${parts[*]}" ;;
  stripe)      echo "${parts[*]}" ;;
  none)        echo "${parts[0]}" ;;
  raidz1)      echo "raidz1 ${parts[*]}" ;;
  raidz2)      echo "raidz2 ${parts[*]}" ;;
  independent) echo "${parts[*]}" ;;
  *)           error "Unknown topology: '$topo'" ;;
  esac
}

# =============================================================================
# STANDALONE DATA POOL TOPOLOGY VALIDATION (ADR 0027)
# =============================================================================

_zfs_validate_pool_topology() {
  # Pure check for a Standalone Data Pool's topology against its disk count.
  # Silent + returns 0 when valid; prints a reason + returns 1 when invalid.
  #
  # Usage: _zfs_validate_pool_topology <topology> <disk_count>
  #
  # 'none' and 'independent' are rejected: build_vdev_spec maps 'none' to the
  # first disk only (silently dropping the rest), and 'independent' has no
  # meaning for a single standalone pool. Operators are pointed to 'stripe'
  # (one non-redundant pool) or multiple data_pools[] entries (separate pools).
  local topo="$1" count="$2" min
  case "$topo" in
  none | independent)
    printf '%s' "topology '${topo}' is not valid for a standalone data" \
      " pool; use 'stripe' for one non-redundant pool, or multiple" \
      " data_pools[] entries for separate pools"
    return 1
    ;;
  stripe) min=1 ;;
  mirror) min=2 ;;
  raidz1) min=2 ;;
  raidz2) min=3 ;;
  *)
    printf '%s' "unknown topology '${topo}'"
    return 1
    ;;
  esac
  if ((count < min)); then
    printf '%s' "topology '${topo}' needs at least ${min} disk(s), got" \
      " ${count}"
    return 1
  fi
  return 0
}

# Filesystem-aware Standalone Data Pool topology check (ADR 0043). A zfs pool
# runs the native vdev validator (_zfs_validate_pool_topology); a non-zfs pool
# (btrfs/ext4/xfs) carries a native topology the zfs validator doesn't know
# (e.g. btrfs raid1), and its validity was already gated by validation.sh's
# _validation_topology_for_fs — so it passes here. Silent + 0 when ok; prints a
# reason + returns 1 on a zfs mismatch. Pure.
_data_pool_topology_ok() {
  local fs="$1" topo="$2" count="$3"
  [[ "$fs" == "zfs" ]] || return 0
  _zfs_validate_pool_topology "$topo" "$count"
}

_zfs_valid_pool_name() {
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

_zfs_redundant_size_mismatch() {
  # Pure decision: returns 0 (warn) when a redundant topology spans disks of
  # differing sizes — ZFS caps usable space to the smallest member. Returns
  # 1 (no warn) for stripe, a single disk, or equal-size redundant disks.
  #
  # Usage: _zfs_redundant_size_mismatch <topology> <size1> [size2] ...
  local topo="$1"
  shift
  local sizes=("$@")
  case "$topo" in
  mirror | raidz1 | raidz2 | raidz3) ;;
  *) return 1 ;; # stripe / none / independent / unknown — never warn
  esac
  ((${#sizes[@]} >= 2)) || return 1
  local first="${sizes[0]}" s
  for s in "${sizes[@]}"; do
    [[ "$s" != "$first" ]] && return 0
  done
  return 1
}
