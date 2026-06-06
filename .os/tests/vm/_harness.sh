#!/usr/bin/env bash
# =============================================================================
# vm/_harness.sh — shared VM test harness
# =============================================================================
# Sourced by testing-*.sh scripts. Do not execute directly.
#
# Variables each script must set before sourcing:
#   VM_NAME          libvirt domain name; also used for disk/log file naming
#   VM_DISK_SIZES[]  GiB per disk; index 0 → /dev/sda, 1 → /dev/sdb, …
#
# Variables each script may set before sourcing (or export from environment):
#   INSTALL_CONFIG_CONTENT  if non-empty: full install.jsonc text written into
#                           the VM, overriding the repo's copy.
#                           if empty (default): repo's install.jsonc is used
#                           with only the hostname patched (single-disk path).
#   REPO_URL                git repo cloned inside the VM
#   TEST_HOSTNAME           hostname patched into install.jsonc
#   VM_RAM_MB               RAM in MiB                    (default: 4096)
#   VM_VCPUS                vCPU count                    (default: 2)
#   TIMEOUT_SEC             install timeout in seconds     (default: 1800)
#   ISO_URL_OVERRIDE   pin a specific ISO URL
#                      (default: auto-resolve)
# =============================================================================

set -Eeuo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${HARNESS_DIR}/../../lib"

# =============================================================================
# DEFAULTS
# =============================================================================
: "${REPO_URL:=https://github.com/Aquastias/Arch-Dotfiles.git}"
: "${TEST_HOSTNAME:=vm-test}"
: "${VM_RAM_MB:=4096}"
: "${VM_VCPUS:=2}"
: "${TIMEOUT_SEC:=${VM_TEST_TIMEOUT:-1800}}"
: "${ISO_URL_OVERRIDE:=}"
: "${INSTALL_CONFIG_CONTENT:=}"
# Boot-verify fixture knobs (single-disk path only). Default off so existing
# fixtures behave identically. DIRTY_CACHE corrupts the live ISO's
# zpool.cache before install; VERIFY_BOOT injects a first-boot sentinel and
# power-cycles to the installed disk to confirm it boots.
: "${DIRTY_CACHE:=false}"
: "${VERIFY_BOOT:=false}"
# Multi-disk only: also assert every pool's leaf vdevs resolve via
# /dev/disk/by-id (regression guard for the disk-reorder bug, ADR 0028).
: "${VM_VERIFY_BYID:=false}"
# Multi-disk only: between install and boot-verify, permute data-disk backing
# files so the system boots with a different /dev/sdX order than it installed
# under — the faithful in-VM repro of the reorder bug (ADR 0028).
: "${VM_REORDER_BOOT_DISKS:=false}"
: "${BOOT_TIMEOUT_SEC:=${VM_BOOT_TIMEOUT:-600}}"
: "${BOOT_LOG_FILE:=${HARNESS_DIR}/${VM_NAME}-boot.log}"

# =============================================================================
# PATHS
# =============================================================================
: "${ISO_DIR:=${HOME}/Downloads}"
: "${CACHE_DIR:=${HARNESS_DIR}/.vm-test}"
: "${LOG_FILE:=${HARNESS_DIR}/${VM_NAME}.log}"

# =============================================================================
# MODULE IMPORTS
# =============================================================================
# shellcheck source=../../lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=../../lib/packages/iso-resolver.sh
source "${LIB_DIR}/packages/iso-resolver.sh"
# shellcheck source=../../lib/sentinel-watcher.sh
source "${LIB_DIR}/sentinel-watcher.sh"
# shellcheck source=../../lib/seed-generator.sh
source "${LIB_DIR}/seed-generator.sh"

# =============================================================================
# CLI
# =============================================================================
usage() {
  cat <<EOF
Usage: $(basename "$0") [--recreate] [--help]

Spins up (or reuses) a libvirt VM that boots the latest Arch live CD,
clones this repo, and runs install.sh --unattended. Streams output to
${LOG_FILE} and exits with the installer's exit code, or 124 on timeout.

Options:
  --recreate     Destroy and undefine the existing VM before creating fresh.
  --verify-boot  After a successful install, power-cycle to the installed
                 disk and wait for the first-boot sentinel on serial.
  -h, --help     Show this help and exit.

All other knobs (REPO_URL, VM hardware, paths, timeout) live as constants
at the top of each testing-*.sh script. Timeout can also be overridden
per-run via the VM_TEST_TIMEOUT environment variable.
EOF
}

RECREATE=false
_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --recreate) RECREATE=true; shift ;;
      --verify-boot) VERIFY_BOOT=true; shift ;;
      -h | --help) usage; exit 0 ;;
      *) echo "[$(basename "$0")] Unknown argument: $1" >&2
         usage >&2; exit 2 ;;
    esac
  done
}

# =============================================================================
# DEPENDENCY / ENVIRONMENT CHECKS
# =============================================================================
_ensure_deps() {
  local missing=()
  command -v virt-install  >/dev/null 2>&1 || missing+=(virt-install)
  command -v virsh         >/dev/null 2>&1 || missing+=(libvirt)
  command -v cloud-localds >/dev/null 2>&1 || missing+=(cloud-image-utils)
  command -v script        >/dev/null 2>&1 || missing+=(util-linux)
  command -v jq            >/dev/null 2>&1 || missing+=(jq)
  if ((${#missing[@]} > 0)); then
    info "Installing missing host dependencies: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
}

_ensure_libvirt_group() {
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx libvirt; then
    error "User '$USER' is not in the 'libvirt' group.
  Run:  sudo usermod -aG libvirt $USER
  Then log out and back in (or run: newgrp libvirt) before retrying."
  fi
}

_ensure_libvirtd() {
  if ! systemctl is-active --quiet libvirtd; then
    info "libvirtd is inactive — starting it now (sudo)."
    sudo systemctl enable --now libvirtd
  fi
}

# =============================================================================
# VM LIFECYCLE
# =============================================================================
_vm_exists()  { virsh dominfo "$VM_NAME" >/dev/null 2>&1; }
_vm_running() {
  [[ "$(virsh domstate "$VM_NAME" 2>/dev/null || true)" == "running" ]]
}

# Returns the source file path of the first cdrom attached to the domain, or
# empty string if none. Used to detect stale ISO references.
_vm_install_iso_path() {
  virsh dumpxml "$VM_NAME" 2>/dev/null |
    sed -n "/device='cdrom'/,/<\/disk>/p" |
    grep -oE "source file='[^']+\.iso'" |
    head -1 |
    sed -E "s/^source file='(.*)'\$/\1/"
}

_vm_destroy_undefine() {
  if _vm_exists; then
    _vm_running && {
      info "Force-stopping VM '${VM_NAME}'."
      virsh destroy "$VM_NAME" >/dev/null
    }
    # Remove only the VM's own data disks — never the cdroms (shared install
    # ISO + seed). libvirt manages ~/Downloads as a storage pool, so
    # --remove-all-storage deletes the reused Arch ISO too; the next run then
    # resolves the cached path, finds the file gone, and fails in _vm_create.
    local own_disks
    own_disks="$(virsh domblklist --details "$VM_NAME" 2>/dev/null \
      | awk '$2 == "disk" { printf "%s%s", sep, $4; sep="," }')"
    info "Undefining VM '${VM_NAME}' (NVRAM + own data disks removed)."
    if [[ -n "$own_disks" ]]; then
      virsh undefine --nvram --storage "$own_disks" "$VM_NAME" >/dev/null
    else
      virsh undefine --nvram "$VM_NAME" >/dev/null
    fi
  fi
}

# Creates the libvirt domain with one qcow2 per entry in VM_DISK_SIZES[],
# plus two read-only CDROMs (install ISO + cloud-init seed).
_vm_create() {
  local iso="$1" seed="$2"
  local disk_args=()
  local i
  for i in "${!VM_DISK_SIZES[@]}"; do
    local disk_path="${CACHE_DIR}/${VM_NAME}-disk${i}.qcow2"
    disk_args+=(--disk \
      "path=${disk_path},size=${VM_DISK_SIZES[$i]},format=qcow2,bus=sata")
  done
  local disk_summary
  disk_summary="$(printf '%sG ' "${VM_DISK_SIZES[@]}")"
  info "Creating VM '${VM_NAME}'" \
       "(${VM_RAM_MB} MiB, ${VM_VCPUS} vCPU, disks: ${disk_summary% })."
  virt-install \
    --name          "$VM_NAME" \
    --memory        "$VM_RAM_MB" \
    --vcpus         "$VM_VCPUS" \
    --osinfo        archlinux \
    --boot          uefi \
    --boot          cdrom,hd \
    "${disk_args[@]}" \
    --disk "path=${iso},device=cdrom,bus=sata,readonly=on" \
    --disk "path=${seed},device=cdrom,bus=sata,readonly=on" \
    --network       network=default \
    --graphics      none \
    --console       pty,target_type=serial \
    --noautoconsole \
    --noreboot
}

_vm_boot_for_run() {
  _vm_running && {
    info "VM is running — force-stopping for clean re-run."
    virsh destroy "$VM_NAME" >/dev/null
  }
  info "Starting VM '${VM_NAME}'."
  virsh start "$VM_NAME" >/dev/null
}

# =============================================================================
# ISO RESOLVER (pinned override)
# =============================================================================
_resolve_pinned_iso() {
  local url="$1" downloads_dir="$2"
  local filename="${url##*/}"
  local target="${downloads_dir%/}/${filename}"
  if [[ -f "$target" ]]; then printf '%s\n' "$target"; return 0; fi
  local tmp="${target}.partial"
  curl -fSL --retry 2 -o "$tmp" "$url" >&2 || {
    rm -f "$tmp"
    error "Pinned ISO download failed: $url"
  }
  mv -f "$tmp" "$target"
  printf '%s\n' "$target"
}

# =============================================================================
# SEED GENERATION
# =============================================================================

# Single-disk path uses lib/seed-generator.sh's tested renderer (single source
# of truth, unit-covered by seed-generator.bats). DIRTY_CACHE / VERIFY_BOOT
# thread through to the boot-verify fixture injections.

# Multi-disk path: clones the repo, overwrites install.jsonc with the
# embedded config (base64-encoded to avoid YAML/shell escaping issues),
# then runs install.sh --unattended.
_render_user_data_multi() {
  local repo_url="$1"
  local config_b64
  config_b64="$(printf '%s' "${INSTALL_CONFIG_CONTENT}" | base64 -w 0)"

  # Optional: inject the multi-disk pool verifier after a successful install.
  # Expectations come from the test script's VM_VERIFY_POOLS / VM_VERIFY_MOUNTS
  # arrays (issue 06). Rendered by lib/seed-generator.sh (unit-covered there).
  local boot_block=""
  if [[ "${VERIFY_BOOT}" == "true" ]]; then
    boot_block="$(_seed_generator_multi_firstboot_block \
      "${VM_VERIFY_POOLS[*]:-}" "${VM_VERIFY_MOUNTS[*]:-}" \
      "${VM_VERIFY_BYID:-false}" "${VM_VERIFY_OWNED[*]:-}")"
  fi

  cat <<EOF
#cloud-config
# Generated by vm/_harness.sh — do not edit by hand.
output: {all: '| tee -a /dev/ttyS0'}
runcmd:
  - |
    set +e
    set -x
    {
      pacman -Sy --noconfirm --needed git \\
        && rm -rf /root/dotfiles \\
        && git clone ${repo_url} /root/dotfiles \\
        && printf '%s' '${config_b64}' | base64 -d \
  > /root/dotfiles/.os/install.jsonc \\
        && cd /root/dotfiles/.os \\
        && ./install.sh --unattended
    }
    rc=\$?
${boot_block}
    printf '===INSTALLER-EXIT-%d===\n' "\$rc" > /dev/ttyS0
    sync
    poweroff -f
EOF
}

_build_seed() {
  local user_data="${CACHE_DIR}/${VM_NAME}-user-data"
  local seed_iso="${CACHE_DIR}/${VM_NAME}-seed.iso"

  if [[ -n "${INSTALL_CONFIG_CONTENT}" ]]; then
    _render_user_data_multi "${REPO_URL}" > "${user_data}"
  else
    _seed_generator_render_user_data \
      "${REPO_URL}" "${TEST_HOSTNAME}" "${DIRTY_CACHE}" "${VERIFY_BOOT}" \
      > "${user_data}"
  fi

  cloud-localds "${seed_iso}" "${user_data}" >/dev/null \
    || error "cloud-localds failed for ${user_data}"
  [[ -s "${seed_iso}" ]] || \
    error "cloud-localds produced empty seed at ${seed_iso}"
  printf '%s\n' "${seed_iso}"
}

# =============================================================================
# CONSOLE CAPTURE
# =============================================================================
# `virsh console --force` requires a controlling TTY for interactive escape
# handling. `script(1)` provides a pseudo-TTY; -f enables line-buffered
# flushes so the user can `tail -F` the log live. script exits when the VM
# powers off (serial pty closes, virsh console drops).

CONSOLE_WRAP_PID=""

_start_console_capture() {
  local log="${1:-$LOG_FILE}"
  : > "$log"
  script -qfc "virsh console --force \"$VM_NAME\"" "$log" >/dev/null 2>&1 &
  CONSOLE_WRAP_PID=$!
  info "Console capture running — \`tail -F ${log}\` to watch live."
}

_stop_console_capture() {
  [[ -n "$CONSOLE_WRAP_PID" ]] || return 0
  pkill -P "$CONSOLE_WRAP_PID" 2>/dev/null || true
  kill  "$CONSOLE_WRAP_PID" 2>/dev/null || true
  wait  "$CONSOLE_WRAP_PID" 2>/dev/null || true
  CONSOLE_WRAP_PID=""
}

# shellcheck disable=SC2329
_on_signal() {
  _stop_console_capture
  exit "$((128 + ${1:-2}))"
}

trap '_stop_console_capture' EXIT
trap '_on_signal 2'  INT
trap '_on_signal 15' TERM

# =============================================================================
# BOOT VERIFY (opt-in)
# =============================================================================
# After a successful install the installed system lives on the HD, but the
# install ISO is still the first boot device. Eject both cdroms so UEFI falls
# through to the ESP (systemd-boot installs the removable BOOTX64.EFI), then
# boot the disk and wait for the first-boot sentinel the fixture injected.

# Eject every cdrom's media on the (shut-off) domain so it cannot boot the ISO.
_eject_cdroms() {
  local tgt
  while read -r tgt; do
    [[ -n "$tgt" ]] || continue
    virsh change-media "$VM_NAME" "$tgt" --eject --config >/dev/null 2>&1 || true
  done < <(virsh domblklist --details "$VM_NAME" 2>/dev/null \
            | awk '$2 == "cdrom" { print $3 }')
}

# Polls virsh ttyconsole until the domain's serial PTY is assigned (or a short
# timeout elapses), so console capture attaches to a live pty instead of dying.
_wait_for_serial_pty() {
  local i
  for i in $(seq 1 50); do
    [[ -n "$(virsh ttyconsole "$VM_NAME" 2>/dev/null)" ]] && return 0
    sleep 0.1
  done
  return 0   # best-effort; console capture surfaces any genuine failure
}

# Boots the installed disk and waits for SEED_GENERATOR_FIRSTBOOT_MARKER on the
# serial console. Returns 0 if the marker appears within BOOT_TIMEOUT_SEC,
# 125 otherwise (distinct from installer exit codes and the 124 timeout).
# Permute data-disk backing files on the (shut-off) domain so the installed
# system boots with a different /dev/sdX order than it installed under. The OS
# disk stays put; only the data disks move. _reorder-disks.py is pure + unit-
# tested (vm-reorder-disks.bats). Faithful in-VM repro of the reorder bug.
_reorder_boot_disks() {
  command -v python3 >/dev/null 2>&1 \
    || { warn "python3 missing — skipping disk reorder."; return 1; }
  local reordered="${CACHE_DIR}/${VM_NAME}-reordered.xml"
  info "Reordering data disks before boot (multi-disk reorder repro)."
  virsh dumpxml --inactive "$VM_NAME" \
    | python3 "${HARNESS_DIR}/_reorder-disks.py" > "$reordered" \
    || { warn "Could not render reordered domain XML."; return 1; }
  virsh define "$reordered" >/dev/null \
    || { warn "Could not define reordered domain."; return 1; }
}

_run_boot_verify() {
  section "Verifying installed system boots (timeout: ${BOOT_TIMEOUT_SEC}s)"
  _eject_cdroms
  _vm_running && virsh destroy "$VM_NAME" >/dev/null 2>&1 || true
  if [[ "${VM_REORDER_BOOT_DISKS}" == "true" ]]; then
    _reorder_boot_disks \
      || warn "Disk reorder failed — boot uses the original disk order."
  fi

  # Start the VM BEFORE attaching console capture. Capturing first races the
  # serial PTY allocation — `virsh console` dies with "PTY device is not yet
  # assigned" and the boot goes unobserved (false 600s timeout). virsh
  # ttyconsole prints the pty path once libvirt wires it up, a beat after start.
  info "Booting installed disk → ${BOOT_LOG_FILE}"
  virsh start "$VM_NAME" >/dev/null
  _wait_for_serial_pty
  _start_console_capture "$BOOT_LOG_FILE"

  local brc=0
  set +e
  sentinel_watcher_wait_marker \
    "$BOOT_LOG_FILE" "$SEED_GENERATOR_FIRSTBOOT_MARKER" "$BOOT_TIMEOUT_SEC"
  brc=$?
  set -e

  _stop_console_capture
  _vm_running && virsh destroy "$VM_NAME" >/dev/null 2>&1 || true

  ((brc == 0)) && return 0
  return 125
}

# =============================================================================
# ENTRY POINT
# =============================================================================
run_harness() {
  _parse_args "$@"
  _ensure_deps
  _ensure_libvirt_group
  _ensure_libvirtd

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
  seed="$(_build_seed)"
  info "Seed: ${seed}"

  section "VM lifecycle"
  if $RECREATE; then _vm_destroy_undefine; fi

  if _vm_exists; then
    local current_iso
    current_iso="$(_vm_install_iso_path)"
    if [[ -n "$current_iso" && "$current_iso" != "$iso" ]]; then
      info "Existing VM points at stale ISO (${current_iso});" \
           "recreating with ${iso}."
      _vm_destroy_undefine
    fi
  fi

  _vm_exists || _vm_create "$iso" "$seed"
  _vm_boot_for_run

  section "Capturing installer log → ${LOG_FILE}"
  # Wait for libvirt to allocate the serial PTY before attaching, exactly as the
  # boot-verify path does. Capturing first races the PTY allocation: `virsh
  # console` dies with "PTY device is not yet assigned", the wrapper exits
  # immediately, and the whole install goes unobserved (empty log → false
  # timeout). This is what made automated runs unwatchable from a non-TTY
  # caller.
  _wait_for_serial_pty
  _start_console_capture

  section "Waiting for installer (timeout: ${TIMEOUT_SEC}s)"
  local rc=0
  set +e
  sentinel_watcher_wait "$LOG_FILE" "$TIMEOUT_SEC"
  rc=$?
  set -e

  _stop_console_capture

  if   ((rc == 124)); then warn "Installer timed out after ${TIMEOUT_SEC}s."
  elif ((rc == 0));   then info "Installer completed successfully (exit 0)."
  else                     warn "Installer finished with exit code ${rc}."
  fi
  info "Log: ${LOG_FILE}"

  # ── Boot verify (opt-in, only after a clean install) ────────────────────────
  if ((rc == 0)) && [[ "$VERIFY_BOOT" == "true" ]]; then
    if _run_boot_verify; then
      info "Installed system reached the first-boot sentinel — boot OK."
    else
      warn "Installed system did NOT reach the first-boot sentinel" \
           "(boot failed or timed out after ${BOOT_TIMEOUT_SEC}s)."
      info "Boot log: ${BOOT_LOG_FILE}"
      rc=125
    fi
  fi

  exit "$rc"
}
