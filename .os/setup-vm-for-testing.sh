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
LOG_FILE="${SCRIPT_DIR}/testing-vm-logs.txt"

# Escape hatch: pin an exact ISO URL. Leave empty to let the harness pick
# the newest archived ISO whose kernel matches a kernel archzfs has prebuilt
# zfs-linux for (see `iso_resolver_get_zfs_compatible` in lib/iso-resolver.sh).
# That dynamic pick avoids the "DKMS build failed" trap that hits when Arch
# bumps its kernel before archzfs catches up.
# Example: ISO_URL_OVERRIDE="https://archive.archlinux.org/iso/2026.04.01/archlinux-2026.04.01-x86_64.iso"
ISO_URL_OVERRIDE=""

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
output to ./testing-vm-logs.txt and exits with the installer's exit code, or
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
  command -v script >/dev/null 2>&1 || missing+=(util-linux)
  command -v jq >/dev/null 2>&1 || missing+=(jq)
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

# Reads the source file of the first cdrom in the domain XML (the install
# ISO — by virt-install convention, sdb in our spec). Empty string if no
# cdrom is attached or the domain doesn't exist.
vm_install_iso_path() {
  # Grab the first <disk device='cdrom'>...</disk> block (sdb = install ISO
  # by virt-install convention), then extract the source file path. The
  # second cdrom (sdc) is the seed.iso, which is never relevant here since
  # the seed is always re-rendered before invocation and lives in CACHE_DIR.
  virsh dumpxml "$VM_NAME" 2>/dev/null |
    sed -n "/device='cdrom'/,/<\/disk>/p" |
    grep -oE "source file='[^']+\.iso'" |
    head -1 |
    sed -E "s/^source file='(.*)'\$/\1/"
}

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

# _resolve_pinned_iso URL DOWNLOADS_DIR
# Cache-aware fetch of a specific ISO URL. Mirrors the iso-resolver contract
# (return cached path if present, else download) but bypasses the
# latest-version lookup. Used when ISO_URL_OVERRIDE is set.
_resolve_pinned_iso() {
  local url="$1" downloads_dir="$2"
  local filename="${url##*/}"
  local target="${downloads_dir%/}/${filename}"
  if [[ -f "$target" ]]; then
    printf '%s\n' "$target"
    return 0
  fi
  local tmp="${target}.partial"
  curl -fSL --retry 2 -o "$tmp" "$url" >&2 || {
    rm -f "$tmp"
    error "Pinned ISO download failed: $url"
  }
  mv -f "$tmp" "$target"
  printf '%s\n' "$target"
}

# =============================================================================
# CONSOLE CAPTURE
# =============================================================================
# `virsh console --force` refuses to run when its stdin/stdout is a pipe —
# it requires a controlling TTY for its interactive escape handling, even
# when we never intend to type into it. Wrapping it with `script(1)` gives
# it a pseudo-TTY; the typescript is written straight to LOG_FILE with
# line-buffered flushes (`-f`) so the user can `tail -F` it live.
#
# `script` exits when the wrapped command exits (poweroff inside the VM
# closes the serial pty, virsh console drops, script returns). On cleanup
# we send SIGTERM to script's PID; it propagates to virsh.

CONSOLE_WRAP_PID=""

start_console_capture() {
  : > "$LOG_FILE"
  script -qfc "virsh console --force \"$VM_NAME\"" "$LOG_FILE" >/dev/null 2>&1 &
  CONSOLE_WRAP_PID=$!
  info "Console capture running — \`tail -F ${LOG_FILE}\` to watch live."
}

stop_console_capture() {
  [[ -n "$CONSOLE_WRAP_PID" ]] || return 0
  pkill -P "$CONSOLE_WRAP_PID" 2>/dev/null || true
  kill "$CONSOLE_WRAP_PID" 2>/dev/null || true
  wait "$CONSOLE_WRAP_PID" 2>/dev/null || true
  CONSOLE_WRAP_PID=""
}

# shellcheck disable=SC2329 # invoked from a `trap` command string below
on_signal() {
  stop_console_capture
  # 128 + signal number; 130 = INT, 143 = TERM. Standard for shell scripts.
  exit "$((128 + ${1:-2}))"
}
trap 'stop_console_capture' EXIT
trap 'on_signal 2' INT
trap 'on_signal 15' TERM

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
  if [[ -n "$ISO_URL_OVERRIDE" ]]; then
    iso="$(_resolve_pinned_iso "$ISO_URL_OVERRIDE" "$ISO_DIR")"
    info "ISO (pinned): ${iso}"
  else
    info "Picking newest archived ISO whose kernel archzfs supports."
    iso="$(iso_resolver_get_zfs_compatible "$ISO_DIR")"
    info "ISO (archzfs-compatible): ${iso}"
  fi

  section "Building cloud-init seed"
  local seed
  seed="$(seed_generator_build "$REPO_URL" "$TEST_HOSTNAME" "$CACHE_DIR")"
  info "Seed: ${seed}"

  section "VM lifecycle"
  if $RECREATE; then
    vm_destroy_undefine
  fi

  # If the resolver picked a different ISO than the existing domain has
  # baked in (e.g. archzfs bumped its kernel pin, or the cached ISO file
  # was deleted), the domain's cdrom reference is stale. Undefine + let
  # the create branch below build a fresh domain that points at the new
  # ISO. Avoids `virsh start` failing with "Cannot access storage file".
  if vm_exists; then
    local current_iso
    current_iso="$(vm_install_iso_path)"
    if [[ -n "$current_iso" && "$current_iso" != "$iso" ]]; then
      info "Existing VM points at stale ISO (${current_iso}); recreating with ${iso}."
      vm_destroy_undefine
    fi
  fi

  if ! vm_exists; then
    vm_create "$iso" "$seed"
  fi
  # virt-install with --noautoconsole --noreboot defines the domain but
  # leaves it shut off on this libvirt version. Reused domains may also
  # be running from a previous run. Both cases are normalised here:
  # force-stop if needed, then start fresh so the console capture below
  # attaches to a guaranteed-running VM.
  vm_boot_for_run

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
