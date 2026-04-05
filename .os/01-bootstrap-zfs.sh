#!/usr/bin/env bash
# =============================================================================
# 01-bootstrap-zfs.sh
# =============================================================================
# PURPOSE:
#   Prepares the official Arch Linux live ISO environment so that ZFS tools
#   are available for the installer. The official ISO ships no ZFS kernel
#   module, so this script adds the archzfs repository, installs the module
#   (pre-built binary if available for the running kernel, DKMS compile
#   otherwise), loads it, and writes /etc/hostid — a file ZFS requires for
#   pool imports.
#
# RUN ORDER:
#   1. 01-bootstrap-zfs.sh   ← you are here
#   2. 02-wipe.sh            (optional — full disk wipe)
#   3. 03-install.sh         (main installer)
#
# REQUIREMENTS:
#   - Booted from the official Arch Linux ISO (2024.xx or later)
#   - UEFI boot mode (not BIOS/legacy)
#   - Internet connection (ethernet recommended; see iwctl for Wi-Fi)
#
# USAGE:
#   chmod +x 01-bootstrap-zfs.sh
#   ./01-bootstrap-zfs.sh
# =============================================================================

set -Eeuo pipefail
trap '_on_error $LINENO' ERR
_on_error() {
  echo -e "\n${RED}[ERROR]${NC} Bootstrap failed at line $1." >&2
  echo -e "${DIM}Check the output above for details.${NC}" >&2
  exit 1
}

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

check_root() {
  [[ $EUID -eq 0 ]] || error "Run as root: sudo -i, then re-run this script."
}

check_uefi() {
  # The installer uses systemd-boot which requires UEFI.
  # /sys/firmware/efi is only present when booted in UEFI mode.
  [[ -d /sys/firmware/efi ]] ||
    error "Not in UEFI mode. Reboot and select UEFI entry in your firmware menu."
  info "UEFI mode confirmed."
}

check_live_env() {
  # The Arch ISO always mounts its root at /run/archiso.
  # Warn (but don't abort) if we can't confirm — some custom ISOs differ.
  if [[ -d /run/archiso ]] || grep -qi 'archiso' /proc/cmdline 2>/dev/null; then
    info "Arch ISO live environment confirmed."
  else
    warn "Could not confirm Arch ISO environment."
    warn "This script is designed for the official Arch Linux ISO."
    read -rp "$(echo -e "${YELLOW}[?]${NC} Continue anyway? [y/N]: ")" _ans
    [[ "${_ans,,}" == "y" ]] || error "Aborted."
  fi
}

check_internet() {
  section "Network"

  # Wait briefly for DHCP to complete if the interface just came up.
  # The Arch ISO starts dhcpcd/NetworkManager in the background at boot;
  # running the script immediately after login can race with it.
  # We check for a default route rather than sleeping a fixed amount.
  local waited=0
  while ((waited < 10)); do
    ip route show default &>/dev/null && break
    info "Waiting for default route... (${waited}s)"
    sleep 1
    ((waited++))
  done

  # Test connectivity by opening a TCP connection to a well-known IP.
  # curl --max-time 3 is faster than ping because:
  #   - ping requires ICMP which some networks/VMs block
  #   - TCP connect returns the moment the SYN-ACK arrives, not after a
  #     full round-trip wait
  #   - We run all three checks in parallel with & and wait for any one
  #     to succeed rather than testing them sequentially
  info "Testing internet connectivity..."

  local ok=false tmpdir
  tmpdir="$(mktemp -d)"

  # Fire all checks in parallel; first success writes a flag file
  for host in 8.8.8.8 1.1.1.1 archlinux.org; do
    (
      if curl -s --max-time 3 --connect-timeout 3 \
        -o /dev/null "http://${host}" 2>/dev/null; then
        touch "${tmpdir}/ok"
      fi
    ) &
  done

  # Wait up to 5 seconds for any parallel check to succeed
  local elapsed=0
  while ((elapsed < 5)); do
    if [[ -f "${tmpdir}/ok" ]]; then
      ok=true
      break
    fi
    sleep 0.5
    ((elapsed++)) || true
  done

  # Reap background jobs
  wait 2>/dev/null || true
  rm -rf "${tmpdir}"

  $ok || error "No internet connection detected.
  Ethernet : should work automatically via DHCP.
  Wi-Fi    : run 'iwctl', then:
               device list
               station wlan0 connect \"<Your Network>\"
  Check route: ip route show default"

  info "Internet connection OK."
}

check_ram() {
  # Refuse to proceed if RAM is genuinely too low.
  # Everything else (cowspace, package cache) lives in RAM on the live ISO,
  # so RAM is the one hard constraint we cannot work around automatically.
  section "Checking RAM"
  local total_ram_mb
  total_ram_mb="$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)"
  info "Total RAM: ${total_ram_mb} MB"

  if ((total_ram_mb < 1024)); then
    error "Only ${total_ram_mb} MB RAM detected. At least 1 GB is required.
  In virt-manager: Machine → Details → Memory — raise to 2048 MB or more."
  elif ((total_ram_mb < 2048)); then
    warn "${total_ram_mb} MB RAM. DKMS build (~900 MB) may run out of space."
    warn "Recommended: 2 GB+ RAM for a reliable DKMS build."
  else
    info "RAM OK: ${total_ram_mb} MB"
  fi
}

expand_cowspace() {
  # The Arch ISO root is an overlay filesystem:
  #   lower = squashfs  (read-only — always appears "full" in df)
  #   upper = /run/archiso/cowspace  (a tmpfs, default size 256 MB)
  #
  # Installing ZFS packages (zfs-linux ~80 MB, zfs-dkms ~900 MB) writes into
  # this upper tmpfs. The default 256 MB fills up immediately.
  #
  # Fix: remount cowspace with a larger size derived from available RAM.
  # This is safe — tmpfs only consumes physical RAM as it is actually written,
  # so allocating "2G" does not immediately use 2 GB of RAM.
  #
  # This function is idempotent: if cowspace is already large enough, it skips.

  section "Expanding cowspace"

  # Only applies to Arch ISO environments
  if ! findmnt /run/archiso/cowspace &>/dev/null 2>&1; then
    info "cowspace not present — not running on Arch ISO, skipping."
    return
  fi

  local cow_total_mb cow_avail_mb total_ram_mb
  cow_total_mb="$(df -m /run/archiso/cowspace | awk 'NR==2{print $2}')"
  cow_avail_mb="$(df -m /run/archiso/cowspace | awk 'NR==2{print $4}')"
  total_ram_mb="$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)"

  info "cowspace current size : ${cow_total_mb} MB"
  info "cowspace available    : ${cow_avail_mb} MB"

  # Target: 75% of total RAM, floored at 1024 MB, capped at total RAM - 512 MB
  # This leaves ~512 MB of RAM for the kernel + running processes.
  local target_mb=$((total_ram_mb * 75 / 100))
  ((target_mb < 1024)) && target_mb=1024
  local cap=$((total_ram_mb - 512))
  ((target_mb > cap && cap > 512)) && target_mb=$cap

  if ((cow_total_mb >= target_mb)); then
    info "cowspace is already ${cow_total_mb} MB — no expansion needed."
    return
  fi

  info "Expanding cowspace: ${cow_total_mb} MB → ${target_mb} MB ..."
  # mount --remount,size= resizes the underlying tmpfs in place.
  # No data is lost; the overlay stays mounted throughout.
  mount -o remount,size="${target_mb}M" /run/archiso/cowspace ||
    error "Failed to expand cowspace.
  This should not happen on the official Arch ISO.
  Try rebooting with  cow_spacesize=2G  on the kernel cmdline as a workaround."

  local new_total_mb
  new_total_mb="$(df -m /run/archiso/cowspace | awk 'NR==2{print $2}')"
  info "cowspace expanded to ${new_total_mb} MB."
}

# =============================================================================
# SYSTEM CLOCK
# =============================================================================

sync_clock() {
  section "System Clock"
  timedatectl set-ntp true
  sleep 2 # give ntpd a moment
  info "NTP enabled. Current time: $(date)"
}

# =============================================================================
# ARCHZFS REPOSITORY
# =============================================================================

add_archzfs_repo() {
  section "Adding archzfs Repository"

  # Remove any stale [archzfs-testing] block before touching the DB.
  # pacman -Sy would fail trying to fetch archzfs-testing.db if it's present.
  _remove_stale_archzfs_testing

  # Initialise and populate the pacman keyring first.
  # On a fresh live ISO this is needed before any new keys can be added.
  info "Refreshing pacman keyring..."
  pacman-key --init
  pacman-key --populate archlinux

  # Update the keyring package itself to avoid "unknown key" errors on older ISOs.
  # -Sy alone (no -u) is safe here because we only need the keyring, not a full upgrade.
  info "Updating archlinux-keyring..."
  pacman -Sy --noconfirm archlinux-keyring

  # ── archzfs repository setup ──────────────────────────────────────────────
  # IMPORTANT: archzfs.com went stale in early 2026. The project moved to
  # GitHub Releases. The new repo is actively maintained and ships current
  # ZFS builds (2.4.x as of April 2026).
  # New repo URL: https://github.com/archzfs/archzfs/releases/download/experimental
  # New signing key: 3A9917BF0DED5C13F69AC68FABEC0A1208037BE9

  local ARCHZFS_KEY="3A9917BF0DED5C13F69AC68FABEC0A1208037BE9"
  local ARCHZFS_SERVER="https://github.com/archzfs/archzfs/releases/download/experimental"

  # Import the new archzfs signing key from keyserver
  info "Importing archzfs signing key (${ARCHZFS_KEY:0:16}...)..."
  pacman-key --recv-keys "$ARCHZFS_KEY" 2>/dev/null || pacman-key --keyserver hkps://keyserver.ubuntu.com --recv-keys "$ARCHZFS_KEY" || error "Failed to import archzfs GPG key.
  Try manually: pacman-key --recv-keys ${ARCHZFS_KEY}"
  pacman-key --lsign-key "$ARCHZFS_KEY"

  # Add [archzfs] repository to pacman.conf if not already present.
  # SigLevel=Never is the current recommendation from the archzfs project
  # while their signing infrastructure is being finalized (see archzfs wiki).
  if grep -q '\[archzfs\]' /etc/pacman.conf; then
    info "[archzfs] repo already present in /etc/pacman.conf"
    # Update stale archzfs.com URL if still present
    if grep -q 'archzfs.com' /etc/pacman.conf; then
      warn "Updating stale archzfs.com repo URL to GitHub ..."
      sed -i "s|Server = https://archzfs.com/.*|Server = ${ARCHZFS_SERVER}|" /etc/pacman.conf
      sed -i '/\[archzfs\]/{n; s/SigLevel.*/SigLevel = Never/}' /etc/pacman.conf 2>/dev/null || true
      info "archzfs repo URL updated."
    fi
  else
    cat >>/etc/pacman.conf <<EOF

# archzfs — ZFS packages for Arch Linux
# Moved from archzfs.com to GitHub Releases in Feb 2026.
# SigLevel=Never is per official archzfs recommendation while signing is finalised.
[archzfs]
SigLevel = Never
Server = ${ARCHZFS_SERVER}
EOF
    info "[archzfs] repo added (GitHub, current)."
  fi

  info "Syncing pacman package databases..."
  pacman -Sy --noconfirm # refresh db after adding archzfs
}

# =============================================================================
# ZFS MODULE INSTALLATION
# =============================================================================
#
# Design:
#   On the live ISO, always use DKMS. The Arch ISO ships the kernel headers for
#   its own kernel at /usr/lib/modules/$(uname -r)/build — DKMS uses exactly
#   those, so the compiled module always matches the running kernel perfectly.
#
#   Pre-built zfs-linux packages are pinned to a specific kernel version and
#   will almost never match the live ISO's kernel exactly. Attempting them leads
#   to version magic mismatches that cannot be worked around.
#
#   The installed system uses zfs-dkms too (configured in lib/packages.sh),
#   which compiles against whatever linux-lts kernel is installed at pacstrap time.

_remove_stale_archzfs_testing() {
  # archzfs-testing no longer exists as a separate repo since the project
  # moved to GitHub in Feb 2026. The single GitHub repo is always current.
  # Remove any stale [archzfs-testing] block left from previous script runs
  # to prevent pacman from trying to fetch a non-existent database.
  if grep -q '\[archzfs-testing\]' /etc/pacman.conf; then
    warn "Removing stale [archzfs-testing] entry from /etc/pacman.conf ..."
    # Delete the [archzfs-testing] block (header + Server line + blank line)
    sed -i '/^\[archzfs-testing\]/,/^$/d' /etc/pacman.conf
    info "[archzfs-testing] removed."
  fi
}

_install_zfs_dkms() {
  # Attempt 2: DKMS build from source.
  #
  # The fundamental problem with DKMS on the live ISO:
  #   - The ISO ships kernel 6.x.y-arch1-1 with headers already present at
  #     /usr/lib/modules/$(uname -r)/build  →  symlink into the source tree.
  #   - BUT: pacman -S linux-headers may pull in a DIFFERENT version if the
  #     mirror has updated since the ISO was cut. DKMS then refuses to build
  #     because the headers version doesn't match the running kernel.
  #
  # Solution: use the headers that are ALREADY on the ISO for the running
  # kernel. The Arch ISO always ships kernel headers at:
  #   /usr/lib/modules/$(uname -r)/build
  # We install zfs-dkms source, then invoke dkms directly pointing at the
  # exact kernel source tree from the ISO — bypassing the version mismatch.

  local kver="$1"

  info "Falling back to DKMS build for kernel ${kver} ..."
  warn "This will take 5–30 minutes depending on CPU speed."
  info "cowspace has been pre-expanded for this build (~900 MB needed)."

  # ── Locate kernel headers for the EXACT running kernel ──────────────────────
  # DKMS needs headers that match the running kernel version precisely.
  # The build directory is /usr/lib/modules/<kver>/build (a symlink to the
  # kernel source tree). Three scenarios:
  #
  #   A) /usr/lib/modules/<kver>/build exists  — ISO ships matching headers.
  #      Use them directly, no download needed.
  #
  #   B) Mirror has the exact matching linux-headers version.
  #      Install it and the /build symlink will be created.
  #
  #   C) Mirror has moved on to a newer version (most common case when the
  #      ISO is a few days old). The exact version is no longer on the mirror
  #      but IS available on the Arch Linux Archive (archive.archlinux.org).
  #      Download it from there and install with pacman -U.

  local kernel_src="/usr/lib/modules/${kver}/build"

  if [[ -d "$kernel_src" ]]; then
    info "Kernel headers already present: ${kernel_src}"

  else
    warn "Kernel headers not found at ${kernel_src}."
    warn "The running kernel (${kver}) does not match the installed headers."

    # Determine the correct headers package name for this kernel flavour
    local headers_pkg="linux-headers"
    echo "$kver" | grep -q '\-lts' && headers_pkg="linux-lts-headers"
    echo "$kver" | grep -q '\-hardened' && headers_pkg="linux-hardened-headers"
    echo "$kver" | grep -q '\-zen' && headers_pkg="linux-zen-headers"

    # Build the exact pkgver string pacman/archive uses.
    # Arch kernel version strings are like: 6.19.10-arch1-1
    # The package version is:               6.19.10.arch1-1  (dot not dash before arch)
    # Convert kernel release string to pacman package version.
    # Kernel: 6.19.10-arch1-1  →  Package: 6.19.10.arch1-1
    # (the hyphen before "arch" becomes a dot in the package version)
    local pkg_ver
    pkg_ver="$(echo "$kver" | sed 's/\([0-9]\)-arch/\1.arch/')"

    info "Need ${headers_pkg}=${pkg_ver}"

    # ── Scenario B: try the current mirror first ──────────────────────────
    info "Attempting to install ${headers_pkg} from current mirror ..."
    if pacman -S --noconfirm --needed "${headers_pkg}=${pkg_ver}" 2>/dev/null &&
      [[ -d "$kernel_src" ]]; then
      info "Headers installed from mirror."

    else
      # ── Scenario C: fetch exact version from Arch Linux Archive ──────
      warn "Exact version not on mirror. Fetching from Arch Linux Archive..."
      warn "URL: https://archive.archlinux.org/packages/"

      # The archive path uses the package name's first letter as a subdir.
      # linux-headers → l/linux-headers/linux-headers-6.19.10.arch1-1-x86_64.pkg.tar.zst
      local arch="x86_64"
      local pkg_file="${headers_pkg}-${pkg_ver}-${arch}.pkg.tar.zst"
      local first_char="${headers_pkg:0:1}"
      local archive_url="https://archive.archlinux.org/packages/${first_char}/${headers_pkg}/${pkg_file}"

      info "Downloading: ${pkg_file}"
      local tmp_pkg="/tmp/${pkg_file}"
      curl -fL --progress-bar "$archive_url" -o "$tmp_pkg" ||
        error "Failed to download headers from Arch Linux Archive.
  URL tried: ${archive_url}
  Check the archive manually: https://archive.archlinux.org/packages/l/${headers_pkg}/
  Then install manually: pacman -U /path/to/${pkg_file}"

      info "Installing headers from archive package ..."
      pacman -U --noconfirm "$tmp_pkg" ||
        error "pacman -U failed for ${tmp_pkg}"
      rm -f "$tmp_pkg"

      [[ -d "$kernel_src" ]] ||
        error "Headers installed but ${kernel_src} still missing.
  This should not happen. Check: ls /usr/lib/modules/${kver}/"
      info "Headers installed from Arch Linux Archive."
    fi
  fi

  # Install the DKMS framework and the ZFS source package.
  # Install DKMS framework and ZFS source package from the archzfs GitHub repo.
  info "Installing dkms + zfs-dkms from archzfs ..."
  if ! pacman -S --noconfirm --needed dkms zfs-dkms zfs-utils 2>/dev/null; then
    warn "zfs-dkms install failed. Retrying after cleanup ..."
    _remove_stale_archzfs_testing
    pacman -Sy --noconfirm # refresh DB after cleanup
    pacman -S --noconfirm --needed dkms zfs-dkms zfs-utils ||
      error "Failed to install zfs-dkms from archzfs.
  Check: pacman -Ss zfs-dkms
  Check: df -h /run/archiso/cowspace  (need ~900 MB free)"
  fi

  # Determine the ZFS version from the installed source directory.
  # zfs-dkms always installs its source to /usr/src/zfs-<version>/.
  # This is more reliable than parsing `dkms status`, whose output format
  # changed in DKMS 3.x (Arch ships DKMS 3.x) from:
  #   old: "zfs, 2.1.x, ..."
  #   new: "zfs/2.1.x, 6.10.x-arch1-1, x86_64: added"
  local zfs_ver
  zfs_ver="$(ls -1 /usr/src/ 2>/dev/null | grep '^zfs-' | sort -V | tail -1 | sed 's/^zfs-//')"
  if [[ -z "$zfs_ver" ]]; then
    error "zfs-dkms installed but /usr/src/zfs-* source directory not found.
  This means the zfs-dkms package did not install correctly.
  Try: pacman -S --noconfirm zfs-dkms && ls /usr/src/zfs-*"
  fi
  info "ZFS source version: ${zfs_ver}"

  # Register the module with DKMS if not already registered.
  # `dkms add` is idempotent — safe to call even if already added.
  dkms add -m zfs -v "$zfs_ver" 2>/dev/null || true

  # Build explicitly against the ISO kernel source tree.
  # --kernelsourcedir overrides DKMS's default header search so it always
  # uses the headers that match the RUNNING kernel, not whatever linux-headers
  # pacman installed (which may be a newer version).
  info "Building ZFS ${zfs_ver} against kernel ${kver} ..."
  info "Build log: /var/lib/dkms/zfs/${zfs_ver}/${kver}/$(uname -m)/log/make.log"

  if ! dkms build -m zfs -v "$zfs_ver" -k "$kver" --kernelsourcedir "$kernel_src"; then
    local makelog="/var/lib/dkms/zfs/${zfs_ver}/${kver}/$(uname -m)/log/make.log"
    echo ""
    warn "DKMS build failed. Last 30 lines of make.log:"
    echo "─────────────────────────────────────────────"
    tail -30 "$makelog" 2>/dev/null || echo "(log not found at ${makelog})"
    echo "─────────────────────────────────────────────"
    echo ""
    error "DKMS build failed for ZFS ${zfs_ver} / kernel ${kver}.
  The most common cause is a ZFS version that does not yet support this kernel.
  Running kernel : ${kver}
  ZFS source     : ${zfs_ver}
  Full log       : ${makelog}
  Possible fixes :
    1. Use an Arch ISO with a kernel that archzfs already tracks.
       Check supported kernels: https://github.com/archzfs/archzfs/releases/tag/experimental
    2. Wait for archzfs to release a build for kernel ${kver}.
    3. Try manually: dkms build zfs/${zfs_ver} -k ${kver} --kernelsourcedir ${kernel_src}"
  fi

  # Install the built module into /lib/modules/<kver>/
  dkms install -m zfs -v "$zfs_ver" -k "$kver" ||
    error "DKMS install failed — module built but could not be installed.
  Try manually: dkms install zfs/${zfs_ver} -k ${kver}"

  info "DKMS build and install complete (ZFS ${zfs_ver})."
}

install_zfs() {
  section "Installing ZFS"

  local kver
  kver="$(uname -r)"
  info "Running kernel: ${kver}"

  # Idempotent — skip if already loaded
  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded — skipping."
    return
  fi

  # Remove any stale testing repo entries before touching pacman
  _remove_stale_archzfs_testing

  # Always DKMS on the live ISO — compiles against the exact running kernel
  _install_zfs_dkms "$kver"
}

load_zfs_module() {
  section "Loading ZFS Kernel Module"

  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded."
    return
  fi

  local kver
  kver="$(uname -r)"

  # Rebuild module index so the kernel finds the newly compiled .ko
  info "Running depmod..."
  depmod -a

  info "Loading ZFS module..."
  modprobe zfs || error "modprobe zfs failed for kernel ${kver}.
  DKMS should have built the module for this exact kernel — check the build log:
    /var/lib/dkms/zfs/*/$(uname -r)/$(uname -m)/log/make.log
  Or re-run: ./01-bootstrap-zfs.sh"

  local zver
  zver="$(modinfo zfs 2>/dev/null | awk '/^version:/{print $2}')"
  info "ZFS module loaded. Version: ${zver:-unknown}"
}

# =============================================================================
# HOSTID
# =============================================================================

setup_hostid() {
  section "Host ID"
  # ZFS stores the hostid in pool metadata. On import it checks that the
  # current system's hostid matches. /etc/hostid must exist and be consistent
  # across reboots. zgenhostid generates a random 4-byte ID and writes it.
  if [[ -f /etc/hostid ]]; then
    info "hostid already exists: $(hostid)"
  else
    zgenhostid
    info "Generated hostid: $(hostid)"
  fi
}

# =============================================================================
# SUMMARY
# =============================================================================

print_summary() {
  section "Bootstrap Complete"
  echo ""
  echo -e "  ${BOLD}The live environment is ready for ZFS installation.${NC}"
  echo ""
  printf "  %-22s %s\n" "Kernel:" "$(uname -r)"
  printf "  %-22s %s\n" "ZFS version:" "$(zfs version 2>/dev/null | head -1 || echo 'unknown')"
  printf "  %-22s %s\n" "hostid:" "$(hostid)"
  printf "  %-22s %s\n" "Time:" "$(date)"
  echo ""
  echo -e "  ${BOLD}Next steps:${NC}"
  echo -e "  ${GREEN}✔${NC}  01-bootstrap-zfs.sh   ${DIM}(done)${NC}"
  echo -e "  ${YELLOW}→${NC}  02-wipe.sh            ${DIM}(optional — wipes all disks to factory blank)${NC}"
  echo -e "  ${DIM}   03-install.sh         (edit install.json first, then run)${NC}"
  echo ""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  echo -e "\n${CYAN}${BOLD}  ZFS Bootstrap — Arch Linux Live ISO${NC}"
  echo -e "${DIM}  ─────────────────────────────────────────────────${NC}\n"

  check_root
  check_uefi
  check_live_env
  check_internet
  check_ram       # hard RAM floor — errors if < 1 GB
  expand_cowspace # remount cowspace larger BEFORE any pacman installs
  sync_clock
  add_archzfs_repo
  install_zfs
  load_zfs_module
  setup_hostid
  print_summary
}

main "$@"ain "$@"
