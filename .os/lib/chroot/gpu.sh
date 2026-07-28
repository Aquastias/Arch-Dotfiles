#!/usr/bin/env bash
# lib/chroot/gpu.sh — Chroot Configuration Module: hybrid GPU hardening
# =============================================================================
# Runs inside arch-chroot, BEFORE initcpio.sh, so the single `mkinitcpio -P`
# bakes in the Early-KMS MODULES and the modprobe.d options in one build. The
# deterministic AMD+NVIDIA hybrid hardening set (ADR 0053) is applied only when
# BOTH vendors are present in the install-state `.gpu` list; otherwise this is a
# no-op and the install is byte-for-byte unchanged.
#
# The pure cores — the gating predicate and the per-artifact text generators —
# are separated from the thin IO seams so the exact emitted config is
# unit-testable without a chroot (mirrors initcpio.sh). Source with
# GPU_LIB_ONLY=1 to load the functions without running any side effects.
# =============================================================================
set -Eeuo pipefail

# The four NVIDIA modules loaded early (KMS) so there is no window where the
# dGPU is half-initialised when the display comes up. Order matters.
_GPU_NVIDIA_MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)

# ── pure: gating ─────────────────────────────────────────────────────────────

# _gpu_should_harden <vendor>... — 0 iff the vendor list contains BOTH amd and
# nvidia (a hybrid laptop). Any single vendor, vm, or empty list → 1.
_gpu_should_harden() {
  local v has_amd=false has_nvidia=false
  for v in "$@"; do
    [[ "$v" == "amd" ]]    && has_amd=true
    [[ "$v" == "nvidia" ]] && has_nvidia=true
  done
  [[ "$has_amd" == true && "$has_nvidia" == true ]]
}

# ── pure: text generators (one per artifact) ─────────────────────────────────

# _gpu_modprobe_conf — /etc/modprobe.d/nvidia.conf content. modeset=1 is
# required for Wayland/PRIME offload; fbdev=1 gives the dGPU an fbdev console.
# PreserveVideoMemoryAllocations keeps VRAM across suspend/resume, and
# TemporaryFilePath saves it under /var/tmp (disk) rather than the default /tmp,
# which is tmpfs (RAM) — a RAM-backed save can fail on resume and black-screen.
# DynamicPowerManagement=0x02 lets the idle dGPU reach D3cold (RTD3).
_gpu_modprobe_conf() {
  cat <<'CONF'
# Hybrid AMD+NVIDIA hardening (ADR 0053) — managed by the installer.
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
options nvidia NVreg_DynamicPowerManagement=0x02
blacklist nouveau
CONF
}

# _gpu_amdgpu_conf — /etc/modprobe.d/amdgpu.conf content. The AMD iGPU drives
# the eDP panel; on Ryzen APUs Panel Self Refresh (PSR) often fails to relight
# it after suspend → black screen on resume. dcdebugmask=0x10 disables PSR (the
# DC_DISABLE_PSR bit), trading a little idle power for a reliable wake.
_gpu_amdgpu_conf() {
  cat <<'CONF'
# Hybrid AMD+NVIDIA hardening (ADR 0053) — managed by the installer.
# Disable Panel Self Refresh: it black-screens the eDP panel on resume.
options amdgpu dcdebugmask=0x10
CONF
}

# _gpu_modules_line <existing-MODULES-content> — the augmented `MODULES=(...)`
# line for /etc/mkinitcpio.conf: the existing tokens with the NVIDIA modules
# appended in order, skipping any already present (idempotent on re-run).
_gpu_modules_line() {
  local existing="$1" out=() seen tok m
  # shellcheck disable=SC2206  # intentional word-split of the MODULES content
  for tok in $existing; do out+=("$tok"); done
  for m in "${_GPU_NVIDIA_MODULES[@]}"; do
    seen=false
    for tok in "${out[@]+"${out[@]}"}"; do
      [[ "$tok" == "$m" ]] && { seen=true; break; }
    done
    [[ "$seen" == false ]] && out+=("$m")
  done
  printf 'MODULES=(%s)\n' "${out[*]+"${out[*]}"}"
}

# _gpu_udev_rule — RTD3 runtime-PM udev rule content. Allows the idle discrete
# GPU (VGA + 3D-controller class variants) to suspend to D3cold on driver bind
# and restores it on unbind.
_gpu_udev_rule() {
  cat <<'RULE'
# NVIDIA dGPU runtime power management (RTD3, ADR 0053).
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
RULE
}

# _gpu_pacman_hook — initramfs-regen hook content. The filename (95-…) sorts it
# AFTER the DKMS hooks so the freshly-built nvidia module exists before the
# image is rebuilt; modeset + Early KMS then survive kernel/driver upgrades.
_gpu_pacman_hook() {
  cat <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = nvidia-open-dkms
Target = nvidia-utils
Target = linux
Target = linux-lts
Target = linux-zen
Target = linux-hardened

[Action]
Description = Rebuilding initramfs after NVIDIA/kernel change (hybrid GPU)...
Depends = mkinitcpio
When = PostTransaction
Exec = /usr/bin/mkinitcpio -P
HOOK
}

# ── thin IO seams (root="" = / in the chroot; tests pass a temp root) ─────────

# _gpu_write_modprobe <root> — install the modprobe.d NVIDIA config.
_gpu_write_modprobe() {
  local root="${1:-}" dir="${1:-}/etc/modprobe.d"
  mkdir -p "$dir"
  _gpu_modprobe_conf > "${dir}/nvidia.conf"
}

# _gpu_write_amdgpu <root> — install the modprobe.d AMD config (PSR disable).
_gpu_write_amdgpu() {
  local dir="${1:-}/etc/modprobe.d"
  mkdir -p "$dir"
  _gpu_amdgpu_conf > "${dir}/amdgpu.conf"
}

# _gpu_write_udev_rule <root> — install the RTD3 udev rule.
_gpu_write_udev_rule() {
  local dir="${1:-}/etc/udev/rules.d"
  mkdir -p "$dir"
  _gpu_udev_rule > "${dir}/80-nvidia-pm.rules"
}

# _gpu_write_pacman_hook <root> — install the initramfs-regen pacman hook.
_gpu_write_pacman_hook() {
  local dir="${1:-}/etc/pacman.d/hooks"
  mkdir -p "$dir"
  _gpu_pacman_hook > "${dir}/95-nvidia-initramfs.hook"
}

# _gpu_apply_modules <conf> — rewrite the MODULES=() line of an mkinitcpio.conf
# in place, appending the NVIDIA modules (idempotent). Appends the line if the
# file has none.
_gpu_apply_modules() {
  local conf="$1" existing newline
  if grep -q '^MODULES=' "$conf"; then
    existing="$(sed -n 's/^MODULES=(\(.*\))/\1/p' "$conf")"
    newline="$(_gpu_modules_line "$existing")"
    sed -i "s|^MODULES=.*|${newline}|" "$conf"
  else
    _gpu_modules_line "" >> "$conf"
  fi
}

# _gpu_enable_services — enable the NVIDIA suspend/resume/hibernate units so
# VRAM is preserved across sleep. Real chroot only.
_gpu_enable_services() {
  systemctl enable nvidia-suspend.service nvidia-resume.service \
    nvidia-hibernate.service
}

# _gpu_harden <root> <conf> <vendor>... — write every on-disk artifact when the
# vendor list gates in (returns non-zero, untouched, when it doesn't). The IO
# seams above do the writing; the suspend/resume/hibernate services are enabled
# separately in the side-effect block since systemctl isn't unit-testable. This
# is the one entry point the side-effect block and the tests share.
_gpu_harden() {
  local root="$1" conf="$2"; shift 2
  _gpu_should_harden "$@" || return 1
  _gpu_write_modprobe   "$root"
  _gpu_write_amdgpu     "$root"
  _gpu_apply_modules    "$conf"
  _gpu_write_udev_rule  "$root"
  _gpu_write_pacman_hook "$root"
}

# Lib-only sourcing for tests: skip all side effects below.
[[ "${GPU_LIB_ONLY:-0}" == "1" ]] && return 0

_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./chroot-common.sh
source "$_LIB_DIR/chroot-common.sh"
chroot_err_trap "gpu"

# shellcheck source=./install-state.sh
STATE="${STATE:-/root/lib-chroot/install-state.json}"
_INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
[[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
# shellcheck disable=SC1090
source "$_INSTALL_STATE_SH"
install_state_load "$STATE"

# GPU is the resolved vendor array from install-state (ADR 0053).
if _gpu_harden "" /etc/mkinitcpio.conf "${GPU[@]+"${GPU[@]}"}"; then
  echo ":: Hybrid AMD+NVIDIA detected — GPU hardening applied (ADR 0053)."
  _gpu_enable_services
else
  echo ":: GPU hardening skipped (not an amd+nvidia hybrid)."
fi
