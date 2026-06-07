#!/usr/bin/env bash
# =============================================================================
# vm/_harness-core.sh — shared core for the VM harnesses
# =============================================================================
# Sourced by BOTH harnesses so their common libvirt host-side logic lives in one
# place instead of copy-pasted:
#   - vm/_harness.sh        — builds persistent, usable VMs
#   - tests/vm/_harness.sh  — drives automated install tests
# Each harness keeps its own divergent behaviour (seed generation, virt-install
# flags, destroy strategy, console capture / installer launch, run_harness flow,
# usage/--verify-boot). Only the genuinely shared pieces live here.
#
# Requires info/warn/error from lib/common.sh (guard-sourced below). Each harness
# sets VM_NAME (and its own vars) before calling these. main()-free — sourcing is
# inert.
# =============================================================================

# common.sh provides info/warn/error used throughout; guard-source so the core
# works whichever harness sources it first (both also source it themselves).
# shellcheck source=../lib/common.sh
[[ "$(type -t info)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../lib/common.sh"

# =============================================================================
# DEPENDENCY / ENVIRONMENT CHECKS
# =============================================================================

# _harness_ensure_deps "cmd:pkg"… — ensure the common libvirt toolchain plus any
# caller-specific extras are installed. pacman --needed, so idempotent.
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

# Returns the source file path of the first cdrom attached to the domain, or
# empty string if none. Used to detect stale ISO references.
_vm_install_iso_path() {
  virsh dumpxml "$VM_NAME" 2>/dev/null |
    sed -n "/device='cdrom'/,/<\/disk>/p" |
    grep -oE "source file='[^']+\.iso'" |
    head -1 |
    sed -E "s/^source file='(.*)'\$/\1/"
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
