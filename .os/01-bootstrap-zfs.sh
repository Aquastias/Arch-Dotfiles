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

# ── Source shared helpers (colours, info/warn/error/section, jsonc, etc.) ─────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# Shared ZFS module install/load — the SAME code 03-install.sh's fallback uses.
# shellcheck source=lib/zfs/module.sh
source "${SCRIPT_DIR}/lib/zfs/module.sh"
# Config accessors — for the any-ZFS gate below (install_config_any_zfs).
# shellcheck source=lib/config/accessors.sh
source "${SCRIPT_DIR}/lib/config/accessors.sh"

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
    error "Not in UEFI mode." \
          "Reboot and select UEFI entry in your firmware menu."
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
    if ip route show default &>/dev/null; then
      break
    fi
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
  local host
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
# ZFS MODULE INSTALLATION
# =============================================================================
#
# The archzfs repo setup and the DKMS build/load live in lib/zfs/module.sh so
# that BOTH this bootstrap and 03-install.sh's fallback share one proven copy
# (zfs_add_archzfs_repo / zfs_install_dkms / zfs_load_module). See ADR 0023.
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
#   The installed system uses zfs-dkms too (configured in lib/packages/list.sh),
#   which compiles against whatever linux-lts kernel is installed
#   at pacstrap time.

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
  zfs_install_dkms "$kver"
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
  printf "  %-22s %s\n" "ZFS version:" \
    "$(zfs version 2>/dev/null | head -1 || echo 'unknown')"
  printf "  %-22s %s\n" "hostid:" "$(hostid)"
  printf "  %-22s %s\n" "Time:" "$(date)"
  echo ""
  echo -e "  ${BOLD}Next steps:${NC}"
  echo -e "  ${GREEN}✔${NC}  01-bootstrap-zfs.sh   ${DIM}(done)${NC}"
  echo -e "  ${YELLOW}→${NC}  02-wipe.sh           " \
          "${DIM}(optional — wipes all disks to factory blank)${NC}"
  echo -e "  ${DIM}   03-install.sh         " \
          "(edit install.json first, then run)${NC}"
  echo ""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  # Skip the whole ZFS bootstrap for a pure non-ZFS install (ADR 0043): the live
  # ISO needs no archzfs repo, no zfs userland, and no zfs module when no group
  # is ZFS. The generic root/UEFI/internet pre-flight is re-run by 03-install.sh,
  # so nothing is lost. <config> is passed by install.sh.
  local cfg="${1:-}"
  if [[ -n "$cfg" && -f "$cfg" ]]; then
    export CONFIG_FILE="$cfg"
    if [[ "$(install_config_any_zfs)" != "true" ]]; then
      info "No ZFS group in the config — skipping ZFS bootstrap (ADR 0043)."
      return 0
    fi
  fi

  echo -e "\n${CYAN}${BOLD}  ZFS Bootstrap — Arch Linux Live ISO${NC}"
  echo -e "${DIM}  ─────────────────────────────────────────────────${NC}\n"

  check_root
  check_uefi
  check_live_env
  check_internet
  check_ram       # hard RAM floor — errors if < 1 GB
  expand_cowspace # remount cowspace larger BEFORE any pacman installs
  sync_clock
  zfs_add_archzfs_repo
  install_zfs
  zfs_load_module
  setup_hostid
  print_summary
}

main "$@"
