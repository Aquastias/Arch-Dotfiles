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
  info "Testing internet connectivity..."
  local ok=false
  for host in archlinux.org archzfs.com 8.8.8.8; do
    if ping -c1 -W3 "$host" &>/dev/null; then
      ok=true
      info "Reachable: $host"
      break
    fi
  done
  $ok || error "No internet connection.
  Ethernet: should work automatically via DHCP.
  Wi-Fi:    run 'iwctl' then: device list → station wlan0 connect <SSID>"
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

install_zfs() {
  section "Installing ZFS"

  local kver
  kver="$(uname -r)"
  info "Running kernel: $kver"

  # Strategy:
  #   1. Try zfs-linux (pre-built binary module for the exact running kernel).
  #      This is fast (~seconds) and preferred.
  #   2. If no pre-built module exists for this kernel, fall back to zfs-dkms
  #      which compiles ZFS from source using DKMS. This takes 5–15 minutes
  #      depending on CPU speed but works on any kernel version.

  # Size note:
  #   zfs-linux (pre-built):  ~40–80 MB download, loads instantly
  #   zfs-dkms + linux-headers + dkms: ~600–900 MB download+build, 5–15 min
  # Always try pre-built first.
  info "Attempting pre-built zfs-linux module..."
  if pacman -S --noconfirm --needed zfs-linux zfs-utils 2>/dev/null; then
    info "Pre-built module installed successfully (~80 MB)."
  else
    warn "No pre-built module for kernel ${kver}. Falling back to DKMS build."
    warn "DKMS will compile ZFS from source. Download + build: ~15–30 min."
    warn "Required cowspace: ~900 MB. cowspace has been auto-expanded by this script."

    # Install linux-headers matching the EXACT running kernel version.
    # 'linux-headers' alone may pull in a different version on some mirrors.
    local headers_pkg="linux-headers"
    # For LTS or hardened kernels running on the ISO (uncommon but possible):
    if uname -r | grep -q 'lts'; then headers_pkg="linux-lts-headers"; fi

    pacman -S --noconfirm --needed "${headers_pkg}" dkms zfs-dkms zfs-utils ||
      error "ZFS DKMS installation failed.
  Check: pacman -Si zfs-dkms   (is the archzfs repo reachable?)
  Check: df -h /run/archiso/cowspace  (is there enough cowspace?)"
    info "DKMS build complete."
  fi
}

load_zfs_module() {
  section "Loading ZFS Kernel Module"

  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded."
    return
  fi

  modprobe zfs || error "Failed to load ZFS kernel module.
  This usually means the DKMS build failed or the module is for a different kernel.
  Try rebooting the ISO and re-running this script."

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

main "$@"ain "$@"ain "$@"
