#!/usr/bin/env bash
# =============================================================================
# vm/_harness.sh — shared harness for persistent usable VM creation
# =============================================================================
# Sourced by vm-*.sh scripts. Do not execute directly.
#
# How installer automation works:
#   1. VM boots Arch live ISO via UEFI. tty1 auto-logs in as root.
#   2. Harness polls virsh domifaddr for the VM's DHCP IP, then waits for
#      the SSH port to be up (confirming the live system is fully booted).
#   3. A minimal HTTP server is started on the host (libvirt bridge IP) to
#      serve the installer shell script.
#   4. virsh send-key types "curl -s <url>|bash" into the VGA console.
#   5. Installer runs, ends with "poweroff". Harness polls until VM is off.
#   6. VM is restarted — UEFI finds the systemd-boot EFI entry written during
#      installation and boots the installed system.
#
# Variables each script must set before sourcing:
#   VM_NAME                 libvirt domain name
#   VM_DISK_SIZES[]         GiB per disk; index 0 → /dev/sda, …
#   INSTALL_CONFIG_CONTENT  full install.jsonc text to write into the VM
#
# Optional overrides (or export from environment):
#   REPO_URL              (default: github repo)
#   VM_RAM_MB             (default: 8192)
#   VM_VCPUS              (default: 4)
#   ISO_URL_OVERRIDE      pin a specific ISO URL
#   LIBVIRT_GATEWAY  libvirt bridge IP the VM can reach
#                    (default: 192.168.122.1)
#   HTTP_PORT             port the host HTTP server listens on (default: 9876)
#   BOOT_TIMEOUT_SEC      seconds to wait for VM IP + SSH (default: 300)
#   INSTALL_TIMEOUT_SEC  seconds to wait for installer to finish
#                        (default: 3600)
# =============================================================================

set -Eeuo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${HARNESS_DIR}/../lib"
# Directory of the VM script that sourced us (vm-kde.sh, vm-secure.sh).
# Used to resolve relative entries in VM_FIXTURE_FILES.
VM_SCRIPT_DIR="${VM_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[1]:-${HARNESS_DIR}/_harness.sh}")" && pwd)}"

# =============================================================================
# DEFAULTS
# =============================================================================
: "${REPO_URL:=https://github.com/Aquastias/Arch-Dotfiles.git}"
: "${VM_RAM_MB:=8192}"
: "${VM_VCPUS:=4}"
: "${ISO_URL_OVERRIDE:=}"
: "${LIBVIRT_GATEWAY:=192.168.122.1}"
: "${HTTP_PORT:=9876}"
: "${BOOT_TIMEOUT_SEC:=300}"
: "${INSTALL_TIMEOUT_SEC:=3600}"

# =============================================================================
# PATHS
# =============================================================================
: "${ISO_DIR:=${HOME}/Downloads}"
: "${CACHE_DIR:=${HARNESS_DIR}/.vm-cache}"

_HTTP_PID=""

# =============================================================================
# MODULE IMPORTS
# =============================================================================
# shellcheck source=../lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=../lib/iso-resolver.sh
source "${LIB_DIR}/iso-resolver.sh"

# =============================================================================
# CLI
# =============================================================================
usage() {
  cat <<EOF
Usage: $(basename "$0") [--recreate] [--help]

Creates a persistent libvirt VM that boots the latest Arch live ISO,
clones this repo, runs install.sh --unattended, then reboots into the
installed system. The installer is triggered automatically.

Options:
  --recreate   Destroy and undefine the existing VM before creating fresh.
  -h, --help   Show this help and exit.
EOF
}

RECREATE=false
_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --recreate) RECREATE=true; shift ;;
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
  command -v nc            >/dev/null 2>&1 || missing+=(openbsd-netcat)
  command -v python3       >/dev/null 2>&1 || missing+=(python)
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
    info "Undefining VM '${VM_NAME}' (storage + NVRAM removed)."
    local i
    for i in "${!VM_DISK_SIZES[@]}"; do
      rm -f "${CACHE_DIR}/${VM_NAME}-disk${i}.qcow2"
    done
    virsh undefine --nvram "$VM_NAME" >/dev/null
  fi
}

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
    --disk "path=${iso},device=cdrom,bus=sata,readonly=on,format=raw" \
    --disk "path=${seed},device=cdrom,bus=sata,readonly=on,format=raw" \
    --network       network=default \
    --graphics      spice,listen=none \
    --video         virtio \
    --channel       spicevmc \
    --console       pty,target_type=serial \
    --noautoconsole \
    --noreboot
}

_vm_boot() {
  _vm_running && {
    info "VM is running — force-stopping."
    virsh destroy "$VM_NAME" >/dev/null
  }
  info "Starting VM '${VM_NAME}'."
  virsh start "$VM_NAME" >/dev/null
}

# =============================================================================
# STORAGE POOL HELPERS
# =============================================================================
_pool_for_dir() {
  local dir
  dir="$(realpath "$1")"
  local name target
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    target="$(virsh pool-dumpxml "$name" 2>/dev/null \
              | sed -n 's|.*<path>\(.*\)</path>.*|\1|p' | head -1)"
    [[ -n "$target" ]] || continue
    target="$(realpath "$target" 2>/dev/null || printf '%s' "$target")"
    [[ "$target" == "$dir" ]] && { printf '%s\n' "$name"; return 0; }
  done < <(virsh pool-list --name 2>/dev/null)
  return 1
}

_refresh_pool_for_path() {
  local pool
  pool="$(_pool_for_dir "$(dirname "$1")" 2>/dev/null)" || return 0
  virsh pool-refresh "$pool" >/dev/null
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
# The seed CDROM is a nocloud ISO whose user-data file is a plain shell script.
# cloud-localds is used only to package it — cloud-init is never invoked.
# The script is served separately via HTTP and launched via virsh send-key.

_render_installer_script() {
  local repo_url="$1"
  local config_b64
  config_b64="$(printf '%s' "${INSTALL_CONFIG_CONTENT}" | base64 -w 0)"
  cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
set -x
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm --needed git
rm -rf /root/dotfiles
git clone ${repo_url} /root/dotfiles
printf '%s' '${config_b64}' | base64 -d > /root/dotfiles/.os/install.jsonc
cd /root/dotfiles/.os
./install.sh --unattended
sync
poweroff
EOF
}

_build_seed() {
  local user_data="${CACHE_DIR}/${VM_NAME}-user-data"
  local seed_iso="${CACHE_DIR}/${VM_NAME}-seed.iso"
  # Empty cloud-config: gives cloud-init a nocloud datasource so it exits
  # immediately without running anything. The installer is launched separately
  # via virsh send-key (see _launch_installer).
  printf '#cloud-config\n' > "${user_data}"
  cloud-localds "${seed_iso}" "${user_data}" >/dev/null \
    || error "cloud-localds failed for ${user_data}"
  [[ -s "${seed_iso}" ]] || \
    error "cloud-localds produced empty seed at ${seed_iso}"
  printf '%s\n' "${seed_iso}"
}

# =============================================================================
# NETWORK HELPERS
# =============================================================================
_get_vm_ip() {
  local elapsed=0 ip
  while true; do
    ip="$(virsh domifaddr "$VM_NAME" 2>/dev/null \
          | awk 'NR>2 { split($4,a,"/"); if (a[1] ~ /^[0-9]/) print a[1] }' \
          | head -1)"
    [[ -n "$ip" ]] && { printf '%s\n' "$ip"; return 0; }
    sleep 5; elapsed=$((elapsed + 5))
    ((elapsed >= BOOT_TIMEOUT_SEC)) && \
      error "Timed out waiting for VM IP address."
  done
}

_wait_for_ssh() {
  local ip="$1" elapsed=0
  info "Waiting for live system to finish booting (SSH port on ${ip})."
  while ! nc -z "$ip" 22 >/dev/null 2>&1; do
    sleep 5; elapsed=$((elapsed + 5))
    ((elapsed >= BOOT_TIMEOUT_SEC)) && \
      error "Timed out waiting for SSH on ${ip}."
  done
  sleep 5  # let tty1 auto-login settle
}

# =============================================================================
# INSTALLER LAUNCH — HTTP server + virsh send-key
# =============================================================================
# Map a single character to one or more virsh key names.
_char_to_keys() {
  case "$1" in
    [a-z]) printf 'KEY_%s'            "${1^^}" ;;
    [0-9]) printf 'KEY_%s'            "$1"     ;;
    ' ')   printf 'KEY_SPACE'                  ;;
    '.')   printf 'KEY_DOT'                    ;;
    '/')   printf 'KEY_SLASH'                  ;;
    '-')   printf 'KEY_MINUS'                  ;;
    ':')   printf 'KEY_LEFTSHIFT KEY_SEMICOLON' ;;
    '|')   printf 'KEY_LEFTSHIFT KEY_BACKSLASH' ;;
    *)     return 1 ;;
  esac
}

_type_into_console() {
  local vm="$1" text="$2"
  local i char keys
  for ((i = 0; i < ${#text}; i++)); do
    char="${text:i:1}"
    if keys="$(_char_to_keys "$char")"; then
      # shellcheck disable=SC2086
      virsh send-key "$vm" $keys >/dev/null 2>&1
    else
      warn "virsh send-key: skipping unmapped character '${char}'"
    fi
    sleep 0.05
  done
  virsh send-key "$vm" KEY_ENTER >/dev/null 2>&1
}

_stop_http_server() {
  [[ -n "${_HTTP_PID}" ]] || return 0
  kill "${_HTTP_PID}" 2>/dev/null || true
  _HTTP_PID=""
}

_stage_fixture_files() {
  local entries=("${VM_FIXTURE_FILES[@]:-}")
  ((${#entries[@]} == 0)) && return 0
  [[ -z "${entries[0]:-}" && ${#entries[@]} -eq 1 ]] && return 0

  declare -A _seen=()
  local entry resolved base dest
  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    if [[ "$entry" = /* ]]; then
      resolved="$entry"
    else
      resolved="${VM_SCRIPT_DIR}/${entry}"
    fi
    [[ -f "$resolved" ]] \
      || error "VM_FIXTURE_FILES: missing source file: $entry"
    base="$(basename "$resolved")"
    [[ "$base" == "run" ]] \
      && error "VM_FIXTURE_FILES: basename collides with installer 'run': $entry"
    [[ -n "${_seen[$base]:-}" ]] \
      && error "VM_FIXTURE_FILES: duplicate basename '$base': $entry"
    _seen[$base]=1
    dest="${CACHE_DIR}/${base}"
    cp -f "$resolved" "$dest"
  done
}

_launch_installer() {
  local script="${CACHE_DIR}/run"
  _render_installer_script "${REPO_URL}" > "${script}"

  python3 -m http.server "${HTTP_PORT}" \
    --directory "${CACHE_DIR}" \
    --bind "${LIBVIRT_GATEWAY}" \
    >/dev/null 2>&1 &
  _HTTP_PID=$!

  local url="http://${LIBVIRT_GATEWAY}:${HTTP_PORT}/run"
  local cmd="curl -s ${url}|bash"
  info "Sending to VGA console: ${cmd}"
  _type_into_console "${VM_NAME}" "${cmd}"
  info "Installer command sent — running inside VM."
}

# =============================================================================
# WAIT FOR COMPLETION
# =============================================================================
_wait_for_poweroff() {
  local elapsed=0
  info "Waiting for installer to finish" \
       "(max ${INSTALL_TIMEOUT_SEC}s — takes 10-30 min)."
  while _vm_running; do
    sleep 15; elapsed=$((elapsed + 15))
    ((elapsed >= INSTALL_TIMEOUT_SEC)) && \
      error "Installer timed out after ${INSTALL_TIMEOUT_SEC}s."
  done
  info "VM powered off — installer complete."
}

# =============================================================================
# ENTRY POINT
# =============================================================================
run_harness() {
  trap '_stop_http_server' EXIT

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
    iso="$(iso_resolver_get_zfs_compatible "$ISO_DIR")"
    info "ISO (archzfs-compatible): ${iso}"
  fi

  section "Building seed CDROM"
  local seed
  seed="$(_build_seed)"
  info "Seed: ${seed}"

  section "VM lifecycle"
  if $RECREATE; then _vm_destroy_undefine; fi

  if _vm_exists; then
    local current_iso
    current_iso="$(_vm_install_iso_path)"
    if [[ -n "$current_iso" && "$current_iso" != "$iso" ]]; then
      info "Existing VM points at stale ISO (${current_iso}); recreating."
      _vm_destroy_undefine
    fi
  fi

  _refresh_pool_for_path "$iso"
  _refresh_pool_for_path "$seed"
  _vm_exists || _vm_create "$iso" "$seed"
  _vm_boot

  section "Waiting for live system"
  local vm_ip
  vm_ip="$(_get_vm_ip)"
  info "VM IP: ${vm_ip}"
  _wait_for_ssh "$vm_ip"

  _stage_fixture_files
  section "Launching installer"
  _launch_installer

  section "Waiting for installer to complete"
  _wait_for_poweroff
  _stop_http_server

  section "Starting installed system"
  # UEFI NVRAM has the systemd-boot EFI entry written by bootctl install.
  # On restart OVMF will find it and boot from the installed disk.
  _vm_boot

  section "Done"
  info "VM '${VM_NAME}' is booting into the installed system."
  info "Open virt-manager and connect to '${VM_NAME}'."
  info "Login: aquastias / 12345  (or root / 12345)"
}
