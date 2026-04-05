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
    warn "${total_ram_mb} MB RAM. Pre-built zfs-linux (~80 MB) will be fine."
    warn "DKMS fallback (~900 MB) may fail — it will only be used if no pre-built exists."
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

  # Initialise and populate the pacman keyring first.
  # On a fresh live ISO this is needed before any new keys can be added.
  info "Refreshing pacman keyring..."
  pacman-key --init
  pacman-key --populate archlinux

  # Update the keyring package itself to avoid "unknown key" errors on older ISOs.
  # -Sy alone (no -u) is safe here because we only need the keyring, not a full upgrade.
  info "Updating archlinux-keyring..."
  pacman -Sy --noconfirm archlinux-keyring

  # Download the archzfs GPG signing key
  info "Fetching archzfs GPG key..."
  local keyfile="/tmp/archzfs.gpg"
  curl -fsSL https://archzfs.com/archzfs.gpg -o "$keyfile" ||
    error "Failed to download archzfs GPG key. Check internet connection."

  # Import the key into pacman's keyring
  pacman-key --add "$keyfile"

  # Extract the key fingerprint so we can locally sign it
  # (pacman requires keys to be locally signed before trusting packages)
  local fp
  fp="$(gpg --with-colons --import-options show-only --import "$keyfile" 2>/dev/null |
    awk 'BEGIN{FS=":"} /^pub/{print $5; exit}')"
  [[ -n "$fp" ]] || error "Could not extract archzfs key fingerprint."
  info "archzfs key fingerprint: $fp"
  pacman-key --lsign-key "$fp"

  # Add [archzfs] repository to pacman.conf if not already present
  if grep -q '\[archzfs\]' /etc/pacman.conf; then
    info "[archzfs] repo already present in /etc/pacman.conf"
  else
    cat >>/etc/pacman.conf <<'EOF'

# archzfs — ZFS packages for Arch Linux
# https://archzfs.com
[archzfs]
Server = https://archzfs.com/$repo/$arch
EOF
    info "[archzfs] repo added to /etc/pacman.conf"
  fi

  info "Syncing pacman package databases..."
  pacman -Sy --noconfirm # refresh db after adding archzfs
}

# =============================================================================
# ZFS MODULE INSTALLATION
# =============================================================================

zfs_module_exists() {
  # Checks for a zfs.ko (or zfs.ko.zst for compressed modules) in the
  # running kernel's module directory. This is the only reliable test —
  # pacman's exit code is not trustworthy for this purpose.
  local kver
  kver="$(uname -r)"
  find "/lib/modules/${kver}" -name "zfs.ko" -o -name "zfs.ko.zst" \
    2>/dev/null | grep -q .
}

_install_zfs_prebuilt() {
  # Attempt 1: archzfs pre-built binary module.
  # The archzfs repo ships zfs-linux packages built against specific kernel
  # versions. This is fast (~80 MB) but only works when the ISO kernel
  # version exactly matches what archzfs has built.
  local kver="$1"
  info "Trying pre-built zfs-linux for kernel ${kver} ..."
  pacman -S --noconfirm --needed zfs-linux zfs-utils 2>/dev/null || true
  zfs_module_exists
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

  # Verify the ISO's own kernel headers are present at the expected path.
  # On the Arch ISO this symlink always exists; on non-ISO systems it may not.
  local kernel_src="/usr/lib/modules/${kver}/build"
  if [[ ! -d "$kernel_src" ]]; then
    # Headers not present — fall back to installing from pacman.
    # Determine the correct package name for this kernel flavour.
    local headers_pkg="linux-headers"
    echo "$kver" | grep -q '\-lts' && headers_pkg="linux-lts-headers"
    echo "$kver" | grep -q '\-hardened' && headers_pkg="linux-hardened-headers"
    echo "$kver" | grep -q '\-zen' && headers_pkg="linux-zen-headers"
    warn "Kernel headers not found at ${kernel_src}."
    warn "Installing ${headers_pkg} from pacman (must match running kernel exactly)."
    pacman -S --noconfirm --needed "$headers_pkg" ||
      error "Failed to install ${headers_pkg}. Mirror may have a newer version.
  Running kernel : ${kver}
  To fix: reboot from a newer Arch ISO whose kernel matches the mirror."
  else
    info "Using ISO kernel headers at: ${kernel_src}"
  fi

  # Install the DKMS framework and the ZFS source package.
  # zfs-dkms contains the ZFS source; DKMS will compile it automatically.
  pacman -S --noconfirm --needed dkms zfs-dkms zfs-utils ||
    error "Failed to install zfs-dkms from archzfs repo.
  Check: pacman -Si zfs-dkms
  Check: df -h /run/archiso/cowspace  (need ~900 MB free)"

  # Run the DKMS build explicitly against the exact kernel tree.
  # This avoids any confusion about which headers DKMS picks up.
  local zfs_ver
  zfs_ver="$(dkms status zfs 2>/dev/null | awk -F'[,/]' '/zfs/{print $2; exit}' | tr -d ' ')"
  if [[ -z "$zfs_ver" ]]; then
    error "zfs-dkms installed but DKMS does not see a ZFS module to build.
  Run: dkms status"
  fi
  info "Building ZFS ${zfs_ver} against kernel ${kver} ..."
  dkms build -m zfs -v "$zfs_ver" -k "$kver" --kernelsourcedir "$kernel_src" ||
    error "DKMS build failed for ZFS ${zfs_ver} / kernel ${kver}.
  Full build log: /var/lib/dkms/zfs/${zfs_ver}/build/make.log
  Common causes:
    - Missing build tools (make, gcc)  →  pacman -S base-devel
    - cowspace full                    →  df -h /run/archiso/cowspace"

  dkms install -m zfs -v "$zfs_ver" -k "$kver" ||
    error "DKMS install step failed — module built but could not be installed."

  info "DKMS build and install complete."
}

install_zfs() {
  section "Installing ZFS"

  local kver
  kver="$(uname -r)"
  info "Running kernel: ${kver}"

  # Already loaded — idempotent re-run
  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded — skipping install."
    return
  fi

  # Try pre-built first; if the .ko doesn't land on disk, use DKMS
  if ! _install_zfs_prebuilt "$kver"; then
    warn "Pre-built module not available for kernel ${kver}."
    _install_zfs_dkms "$kver"
  fi

  # Final verification — must have the .ko before we try modprobe
  if ! zfs_module_exists; then
    error "ZFS module file still not found in /lib/modules/${kver}/ after all attempts.
  Run manually to diagnose:
    dkms status
    ls /lib/modules/${kver}/extra/
    journalctl -b | grep -i 'dkms\|zfs'"
  fi

  info "ZFS module verified in /lib/modules/${kver}/."
}
load_zfs_module() {
  section "Loading ZFS Kernel Module"

  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded — skipping modprobe."
    return
  fi

  # Run depmod so the kernel module index knows about the newly installed .ko.
  # This is required after installing a module outside of the normal boot path.
  info "Updating kernel module index (depmod)..."
  depmod -a

  info "Loading ZFS module..."
  modprobe zfs || error "modprobe zfs failed.
  Kernel : $(uname -r)
  Module : $(find /lib/modules/$(uname -r) -name 'zfs.ko*' 2>/dev/null | head -1 || echo 'NOT FOUND')
  Try:
    depmod -a && modprobe zfs
  If the module is still missing, re-run 01-bootstrap-zfs.sh from scratch."

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

main "$@"ain "$@"ain "$@"ain "$@"ain "$@"ain "$@"
