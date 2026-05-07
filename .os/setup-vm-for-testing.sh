#!/usr/bin/env bash
# =============================================================================
# setup-vm-for-testing.sh — VM test harness for the Arch Linux ZFS installer
# =============================================================================
# Composes:
#   lib/iso-resolver.sh     — resolves & caches the latest Arch ISO
#   lib/seed-generator.sh   — builds the cloud-init NoCloud seed.iso
#   lib/sentinel-watcher.sh — waits for ===INSTALLER-EXIT-N=== in the log
#
# Flow:
#   1. Install missing host deps (virt-install, libvirt, cloud-image-utils)
#   2. Verify libvirt group membership; ensure libvirtd is active
#   3. Resolve the latest Arch ISO (download once, then cache-hit)
#   4. Regenerate the cloud-init seed (REPO_URL + TEST_HOSTNAME)
#   5. Create the libvirt VM (or destroy + recreate if --recreate)
#      — UEFI, SATA disk + 2× SATA CD-ROMs (ISO + seed), boot CD-ROM then HD
#   6. Capture serial-console output to LOG_FILE via `virsh console | tee`
#   7. Wait for the installer's sentinel; exit with its code (124 on timeout)
#
# All tunables live as constants at the top of the script. The CLI is two
# flags only: --recreate and --help.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# TUNABLES — edit here, not via flags
# =============================================================================

# The repo cloned inside the test VM. Point this at a fork to test changes.
# The VM clones whatever is on the configured branch's tip, so `git push`
# before running this script.
REPO_URL="https://github.com/Aquastias/Arch-Dotfiles.git"

# Libvirt domain name. Reused across runs unless --recreate is passed.
VM_NAME="arch-zfs-installer-test"

# VM hardware spec. Match the existing single-disk install.jsonc layout.
VM_RAM_MB=4096
VM_VCPUS=2
VM_DISK_GB=40

# Where the harness reads/writes filesystem artefacts.
ISO_DIR="${HOME}/Downloads"
CACHE_DIR="${SCRIPT_DIR}/.vm-test"
LOG_FILE="${SCRIPT_DIR}/testing-vm-logs"

# Hard timeout for a full install. Override per-run via VM_TEST_TIMEOUT.
TIMEOUT_SEC="${VM_TEST_TIMEOUT:-1800}"

# Hostname patched into install.jsonc inside the VM by the cloud-init seed.
TEST_HOSTNAME="vm-test"

# =============================================================================
# MODULE IMPORTS
# =============================================================================

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/iso-resolver.sh
source "${SCRIPT_DIR}/lib/iso-resolver.sh"
# shellcheck source=lib/seed-generator.sh
source "${SCRIPT_DIR}/lib/seed-generator.sh"
# shellcheck source=lib/sentinel-watcher.sh
source "${SCRIPT_DIR}/lib/sentinel-watcher.sh"

# =============================================================================
# CLI
# =============================================================================

usage() {
  cat <<'EOF'
Usage: setup-vm-for-testing.sh [--recreate] [--help]

Spins up (or reuses) a libvirt VM that boots the latest Arch live CD,
clones this repo, and runs install.sh --unattended. Streams the installer's
output to ./testing-vm-logs and exits with the installer's exit code, or
124 on timeout.

Options:
  --recreate   Force-destroy and undefine the existing VM (including its
               qcow2 disk and NVRAM) before creating a fresh one. Use this
               to recover from a wedged disk state.
  -h, --help   Show this help and exit.

All other knobs (REPO_URL, VM hardware, paths, timeout) live as constants
at the top of this script. The timeout can also be overridden per-run via
the VM_TEST_TIMEOUT environment variable.
EOF
}

RECREATE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --recreate)
      RECREATE=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "[setup-vm-for-testing.sh] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# =============================================================================
# DEPENDENCY / ENVIRONMENT CHECKS
# =============================================================================

ensure_deps() {
  local missing=()
  command -v virt-install >/dev/null 2>&1 || missing+=(virt-install)
  command -v virsh >/dev/null 2>&1 || missing+=(libvirt)
  command -v cloud-localds >/dev/null 2>&1 || missing+=(cloud-image-utils)
  if ((${#missing[@]} > 0)); then
    info "Installing missing host dependencies: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
}

ensure_libvirt_group() {
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx libvirt; then
    error "User '$USER' is not in the 'libvirt' group.
  Run:  sudo usermod -aG libvirt $USER
  Then log out and back in (or run: newgrp libvirt) before retrying."
  fi
}

ensure_libvirtd() {
  if ! systemctl is-active --quiet libvirtd; then
    info "libvirtd is inactive — starting it now (sudo)."
    sudo systemctl enable --now libvirtd
  fi
}

# =============================================================================
# VM LIFECYCLE
# =============================================================================

vm_exists() { virsh dominfo "$VM_NAME" >/dev/null 2>&1; }
vm_running() { [[ "$(virsh domstate "$VM_NAME" 2>/dev/null || true)" == "running" ]]; }

vm_destroy_undefine() {
  if vm_exists; then
    if vm_running; then
      info "Force-stopping existing VM '${VM_NAME}'."
      virsh destroy "$VM_NAME" >/dev/null
    fi
    info "Undefining existing VM '${VM_NAME}' (storage + NVRAM removed)."
    virsh undefine --remove-all-storage --nvram "$VM_NAME" >/dev/null
  fi
}

vm_create() {
  local iso="$1" seed="$2"
  local disk="${CACHE_DIR}/${VM_NAME}.qcow2"

  info "Creating VM '${VM_NAME}' (${VM_RAM_MB} MiB RAM, ${VM_VCPUS} vCPU, ${VM_DISK_GB} GiB disk)."
  virt-install \
    --name "$VM_NAME" \
    --memory "$VM_RAM_MB" \
    --vcpus "$VM_VCPUS" \
    --osinfo archlinux \
    --boot uefi \
    --boot cdrom,hd \
    --disk "path=${disk},size=${VM_DISK_GB},format=qcow2,bus=sata" \
    --disk "path=${iso},device=cdrom,bus=sata,readonly=on" \
    --disk "path=${seed},device=cdrom,bus=sata,readonly=on" \
    --network network=default \
    --graphics none \
    --console pty,target_type=serial \
    --noautoconsole \
    --noreboot
}

vm_boot_for_run() {
  if vm_running; then
    info "VM is running — force-stopping for a clean re-run."
    virsh destroy "$VM_NAME" >/dev/null
  fi
  info "Starting VM '${VM_NAME}'."
  virsh start "$VM_NAME" >/dev/null
}

# =============================================================================
# CONSOLE CAPTURE
# =============================================================================
# `virsh console --force "$VM_NAME" | tee LOG_FILE` is run inside a wrapper
# subshell so we can identify and kill the whole pipeline on cleanup. The
# wrapper PID is the parent of `virsh` and `tee`; pkill -P kills both.

CONSOLE_WRAP_PID=""

start_console_capture() {
  : > "$LOG_FILE"
  { virsh console --force "$VM_NAME" 2>&1 | tee -a "$LOG_FILE"; } &
  CONSOLE_WRAP_PID=$!
}

stop_console_capture() {
  [[ -n "$CONSOLE_WRAP_PID" ]] || return 0
  pkill -P "$CONSOLE_WRAP_PID" 2>/dev/null || true
  kill "$CONSOLE_WRAP_PID" 2>/dev/null || true
  wait "$CONSOLE_WRAP_PID" 2>/dev/null || true
  CONSOLE_WRAP_PID=""
}

trap 'stop_console_capture' EXIT INT TERM

# =============================================================================
# MAIN
# =============================================================================

main() {
  ensure_deps
  ensure_libvirt_group
  ensure_libvirtd

  mkdir -p "$ISO_DIR" "$CACHE_DIR"

  section "Resolving Arch ISO"
  local iso
  iso="$(iso_resolver_get "$ISO_DIR")"
  info "ISO: ${iso}"

  section "Building cloud-init seed"
  local seed
  seed="$(seed_generator_build "$REPO_URL" "$TEST_HOSTNAME" "$CACHE_DIR")"
  info "Seed: ${seed}"

  section "VM lifecycle"
  if $RECREATE; then
    vm_destroy_undefine
  fi
  if ! vm_exists; then
    vm_create "$iso" "$seed"
  else
    vm_boot_for_run
  fi

  section "Capturing installer log → ${LOG_FILE}"
  start_console_capture

  section "Waiting for installer (timeout: ${TIMEOUT_SEC}s)"
  local rc=0
  set +e
  sentinel_watcher_wait "$LOG_FILE" "$TIMEOUT_SEC"
  rc=$?
  set -e

  stop_console_capture

  if ((rc == 124)); then
    warn "Installer did not finish before the ${TIMEOUT_SEC}s timeout."
  elif ((rc == 0)); then
    info "Installer completed successfully (exit 0)."
  else
    warn "Installer finished with exit code ${rc}."
  fi
  info "Log file: ${LOG_FILE}"

  exit "$rc"
}

main
