#!/usr/bin/env bash
# =============================================================================
# vm/lib/core.sh — shared host-side core for the VM Harness
# =============================================================================
# Sourced by vm/vm.sh alongside exactly one flow module (flow-persistent.sh or
# flow-test.sh). Absorbs the former vm/_harness-core.sh plus the pieces both
# old harnesses shared: dependency checks, libvirt group/daemon ensure, ISO
# resolution, VM state predicates, domain create/boot/destroy, storage-pool
# refresh, and VM_FIXTURE_FILES staging.
#
# A library: sourcing is inert (no top-level work beyond defaults). The flow
# module supplies the per-flow virt-install graphics flags via FLOW_GRAPHICS_ARGS
# and the seed builder via _flow_build_seed; the caller (vm.sh) sets VM_NAME,
# VM_DISK_SIZES[], VM_RAM_MB, VM_VCPUS, CACHE_DIR before invoking these.
# =============================================================================

CORE_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
CORE_LIB_DIR="${CORE_DIR}/../../lib"

# common.sh provides info/warn/error/section; guard-source so a flow or test
# that already sourced it does not re-run it.
# shellcheck source=../../lib/common.sh
[[ "$(type -t info)" == "function" ]] \
  || source "${CORE_LIB_DIR}/common.sh"
# shellcheck source=../../lib/packages/iso-resolver.sh
source "${CORE_LIB_DIR}/packages/iso-resolver.sh"

# =============================================================================
# SHARED DEFAULTS (env overrides win)
# =============================================================================
: "${REPO_URL:=https://github.com/Aquastias/Arch-Dotfiles.git}"
: "${ISO_URL_OVERRIDE:=}"
: "${ISO_DIR:=${HOME}/Downloads}"
: "${LIBVIRT_GATEWAY:=192.168.122.1}"

# =============================================================================
# DEPENDENCY / ENVIRONMENT CHECKS
# =============================================================================
# _harness_ensure_deps "cmd:pkg"… — ensure the common libvirt toolchain plus any
# flow-specific extras are installed. pacman --needed, so idempotent.
_harness_ensure_deps() {
  local common=(virt-install:virt-install virsh:libvirt \
                cloud-localds:cloud-image-utils jq:jq)
  local missing=() pair cmd pkg
  for pair in "${common[@]}" "$@"; do
    cmd="${pair%%:*}"; pkg="${pair##*:}"
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$pkg")
  done
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
# VM STATE PREDICATES
# =============================================================================
_vm_exists()  { virsh dominfo "$VM_NAME" >/dev/null 2>&1; }
_vm_running() {
  [[ "$(virsh domstate "$VM_NAME" 2>/dev/null || true)" == "running" ]]
}

# Source file path of the first cdrom attached to the domain, or empty if none.
# Used to detect stale ISO references.
_vm_install_iso_path() {
  virsh dumpxml "$VM_NAME" 2>/dev/null |
    sed -n "/device='cdrom'/,/<\/disk>/p" |
    grep -oE "source file='[^']+\.iso'" |
    head -1 |
    sed -E "s/^source file='(.*)'\$/\1/"
}

# =============================================================================
# ISO RESOLUTION
# =============================================================================
# Pinned-override download: cache <downloads_dir>/<basename>, fetch if absent.
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

# core_resolve_iso <iso_dir> — pinned override else newest archzfs-compatible.
# Prints the ISO path on stdout; status/info on stderr.
core_resolve_iso() {
  local iso_dir="$1" iso
  if [[ -n "$ISO_URL_OVERRIDE" ]]; then
    iso="$(_resolve_pinned_iso "$ISO_URL_OVERRIDE" "$iso_dir")"
    info "ISO (pinned): ${iso}" >&2
  else
    info "Picking newest archived ISO whose kernel archzfs supports." >&2
    iso="$(iso_resolver_get_zfs_compatible "$iso_dir")"
    info "ISO (archzfs-compatible): ${iso}" >&2
  fi
  printf '%s\n' "$iso"
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

# Refresh the libvirt storage pool backing <path>'s directory, so a freshly
# downloaded ISO/seed is visible to the domain. No-op when not pool-backed.
_refresh_pool_for_path() {
  local pool
  pool="$(_pool_for_dir "$(dirname "$1")" 2>/dev/null)" || return 0
  virsh pool-refresh "$pool" >/dev/null
}

# =============================================================================
# DOMAIN LIFECYCLE
# =============================================================================
# Removes the domain plus its OWN data disks (never the shared install ISO /
# seed cdroms) and its NVRAM. libvirt manages ~/Downloads as a pool, so a blanket
# --remove-all-storage would delete the reused Arch ISO; --storage on the disk
# targets keeps it.
_vm_destroy_undefine() {
  _vm_exists || return 0
  _vm_running && {
    info "Force-stopping VM '${VM_NAME}'."
    virsh destroy "$VM_NAME" >/dev/null
  }
  local own_disks
  own_disks="$(virsh domblklist --details "$VM_NAME" 2>/dev/null \
    | awk '$2 == "disk" { printf "%s%s", sep, $4; sep="," }')"
  info "Undefining VM '${VM_NAME}' (NVRAM + own data disks removed)."
  if [[ -n "$own_disks" ]]; then
    virsh undefine --nvram --storage "$own_disks" "$VM_NAME" >/dev/null
  else
    virsh undefine --nvram "$VM_NAME" >/dev/null
  fi
}

# Creates the libvirt domain with one qcow2 per entry in VM_DISK_SIZES[], plus
# two read-only cdroms (install ISO + seed). The flow module supplies the
# graphics/video/channel flags via FLOW_GRAPHICS_ARGS[].
_vm_create() {
  local iso="$1" seed="$2"
  local disk_args=() i
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
    "${FLOW_GRAPHICS_ARGS[@]}" \
    --console       pty,target_type=serial \
    --noautoconsole \
    --noreboot
}

# Start the domain, force-stopping a stale running instance first.
_vm_boot() {
  _vm_running && {
    info "VM is running — force-stopping for a clean start."
    virsh destroy "$VM_NAME" >/dev/null
  }
  info "Starting VM '${VM_NAME}'."
  virsh start "$VM_NAME" >/dev/null
}

# Eject every cdrom (install ISO + seed) from the domain so a subsequent boot
# falls through to the installed disk's systemd-boot entry instead of the live
# ISO (the domain is created --boot cdrom,hd). Shared by both flows; operates on
# the persistent config so it survives the next start. Best-effort, never fatal.
_vm_eject_cdroms() {
  local tgt
  while read -r tgt; do
    [[ -n "$tgt" ]] || continue
    virsh change-media "$VM_NAME" "$tgt" --eject --config >/dev/null 2>&1 || true
  done < <(virsh domblklist --details "$VM_NAME" 2>/dev/null \
            | awk '$2 == "cdrom" { print $3 }')
}

# =============================================================================
# FIXTURE STAGING (VM_FIXTURE_FILES → CACHE_DIR)
# =============================================================================
# Copies each declared fixture into CACHE_DIR so the flow's HTTP server can
# serve it (e.g. the secure profile's Test Age Key). Relative entries resolve
# against VM_SCRIPT_DIR. Basenames must be unique and must not collide with the
# installer 'run' script. Unset/empty array is a no-op.
# _fixture_http_should_serve — true (0) iff any fixture is declared, so a flow
# only stands up the fixture HTTP server when something needs serving. Same
# unset/empty guard as _stage_fixture_files; pure (reads VM_FIXTURE_FILES only).
_fixture_http_should_serve() {
  local entries=("${VM_FIXTURE_FILES[@]:-}")
  ((${#entries[@]} == 0)) && return 1
  [[ -z "${entries[0]:-}" && ${#entries[@]} -eq 1 ]] && return 1
  return 0
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
