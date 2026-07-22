#!/usr/bin/env bash
# =============================================================================
# lib/config/environment.sh — Environment validation and hardware resolution
# =============================================================================
# Sourced by lib/config/lifecycle.sh.
# Requires: lib/common.sh already sourced (provides error, warn, jsonc_strip,
#           and CONFIG_FILE global).
#
# Public API:
#   resolve_environment — idempotent; populates ENVIRONMENT_DESKTOP,
#                         ENVIRONMENT_GPU, GPU_PACMAN_PACKAGES,
#                         GPU_PARU_PACKAGES, AUDIO_PACKAGES from
#                         CONFIG_FILE.
# =============================================================================

# ── RESOLVED GLOBALS ─────────────────────────────────────────────────────────
# Set by _resolve_env_validate; consumed by _resolve_env_gpu,
# _resolve_env_audio, and collect_packages.
# shellcheck disable=SC2034
ENVIRONMENT_DESKTOP=()
# shellcheck disable=SC2034
ENVIRONMENT_GPU=()

# Set by _resolve_env_gpu; consumed by collect_packages.
# Declared here so collect_packages can detect unresolved state.
GPU_PACMAN_PACKAGES=()
GPU_PARU_PACKAGES=()

# Set by _resolve_env_audio; consumed by collect_packages.
AUDIO_PACKAGES=()

# ── VALID VALUE SETS ──────────────────────────────────────────────────────────
_VALID_DESKTOP=(kde hyprland)
_VALID_GPU=(amd nvidia intel auto)

# =============================================================================
# GPU RESOLUTION
# =============================================================================

# Wraps lspci -nn. Override in tests to control hardware detection.
_gpu_lspci_output() { lspci -nn 2>/dev/null; }

# Resolve GPU vendor string → package list entry.
_gpu_vendor_packages() {
  local vendor="$1"
  case "$vendor" in
    amd)    echo "vulkan-radeon xf86-video-amdgpu mesa" ;;
    nvidia)
      echo "nvidia-open-dkms nvidia-utils lib32-nvidia-utils" \
           "libva-nvidia-driver egl-wayland"
      ;;
    intel)
      local lspci_out device_id dec_id
      lspci_out="$(_gpu_lspci_output)"
      device_id="$(echo "$lspci_out" | grep -i "intel" \
        | grep -oP '8086:\K[0-9a-fA-F]+' | head -1)"
      if [[ -n "$device_id" ]]; then
        dec_id=$(( 16#$device_id ))
        if (( dec_id >= 0x1600 )); then
          echo "intel-media-driver"
        else
          echo "libva-intel-driver"
        fi
      else
        echo "intel-media-driver"
      fi
      ;;
    vm) echo "mesa" ;;
  esac
}

# Detect GPU vendors from lspci output. Emits one vendor per line.
# Returns "vm" for recognised VM GPUs; nothing for unknown.
_gpu_detect_vendors() {
  local lspci_out
  lspci_out="$(_gpu_lspci_output)"
  local found=false

  if echo "$lspci_out" \
      | grep -qiP '15ad:|1af4:1050|VMware|Virtio GPU|VirtualBox'; then
    echo "vm"
    return
  fi

  echo "$lspci_out" | grep -qi '1002:'  && { echo "amd";    found=true; }
  echo "$lspci_out" | grep -qi '10de:'  && { echo "nvidia"; found=true; }
  echo "$lspci_out" | grep -qi '8086:'  && { echo "intel";  found=true; }

  if ! $found; then
    warn "GPU auto-detection: no recognised vendor in lspci output" \
         "— using mesa fallback."
    echo "vm"
  fi
}

# Translate ENVIRONMENT_GPU → GPU_PACMAN_PACKAGES + GPU_PARU_PACKAGES.
# If ENVIRONMENT_GPU=("auto"), runs lspci detection and updates ENVIRONMENT_GPU.
_resolve_env_gpu() {
  GPU_PACMAN_PACKAGES=()
  GPU_PARU_PACKAGES=()

  if [[ "${#ENVIRONMENT_GPU[@]}" -eq 1 \
     && "${ENVIRONMENT_GPU[0]}" == "auto" ]]; then
    mapfile -t ENVIRONMENT_GPU < <(_gpu_detect_vendors)
  fi

  for _vendor in "${ENVIRONMENT_GPU[@]}"; do
    local _pkgs
    _pkgs="$(_gpu_vendor_packages "$_vendor")"
    # shellcheck disable=SC2206
    GPU_PACMAN_PACKAGES+=( $_pkgs )
  done

  local _has_amd=false _has_nvidia=false
  for _v in "${ENVIRONMENT_GPU[@]}"; do
    [[ "$_v" == "amd" ]]    && _has_amd=true
    [[ "$_v" == "nvidia" ]] && _has_nvidia=true
  done
  [[ "$_has_amd" == "true" && "$_has_nvidia" == "true" ]] \
    && GPU_PARU_PACKAGES+=( envycontrol ) || true
}

# =============================================================================
# HYBRID GPU SESSION ENV (nvidia PRIME laptops)
# =============================================================================
# nvidia PRIME laptops wire the internal panel to the integrated GPU (amd/intel);
# the nvidia dGPU only renders (offload). A Wayland compositor that scans out on
# the nvidia node — Hyprland/aquamarine picks the first DRM device, often nvidia —
# renders to a display the panel can't show → black screen (KDE/KWin negotiates
# this itself; Hyprland does not). AQ_DRM_DEVICES=<igpu>:<dgpu> makes Hyprland use
# the panel's GPU first. Emitted to /etc/environment so PAM applies it to EVERY
# session (no uwsm needed); written before the impermanence @blank snapshot so it
# survives the /etc rollback. Stable PCI by-path nodes — /dev/dri/cardN numbers
# are not stable across boots.
#
# ONLY AQ_DRM_DEVICES is written: it is Hyprland/aquamarine-specific and inert to
# every other client. Do NOT add global LIBVA_DRIVER_NAME / __GLX_VENDOR_LIBRARY
# _NAME / NVD_BACKEND here — those force the offload (nvidia) driver on EVERY GL/
# VA client, including the SDDM greeter and KDE, which run on the iGPU-driven
# panel → the greeter renders a blank grey screen (regression, fixed here). Per-
# app nvidia offload is a runtime concern (prime-run), not a global default.

# Wraps `lspci -D -nn` (domain-qualified). Override in tests.
_gpu_lspci_output_d() { lspci -D -nn 2>/dev/null; }

# PCI address (e.g. 0000:34:00.0) of the first VGA/3D/Display device for a PCI
# vendor id (1002 amd, 8086 intel, 10de nvidia). Empty when absent.
_gpu_pci_addr_for_vendor() {
  local vid="$1"
  _gpu_lspci_output_d \
    | grep -iE 'VGA compatible|3D controller|Display controller' \
    | grep -iF "[${vid}:" | head -1 | awk '{print $1}'
}

# Emit the AQ_DRM_DEVICES by-path pair (integrated GPU first) when the resolved
# GPU set is an nvidia + integrated hybrid; empty otherwise. Pure (reads lspci).
gpu_hybrid_aq_drm_devices() {
  local _has_nv=false _v
  for _v in "${ENVIRONMENT_GPU[@]:-}"; do [[ "$_v" == nvidia ]] && _has_nv=true; done
  [[ "$_has_nv" == true ]] || return 0
  local _igpu _nv
  _igpu="$(_gpu_pci_addr_for_vendor 1002)"
  [[ -n "$_igpu" ]] || _igpu="$(_gpu_pci_addr_for_vendor 8086)"
  _nv="$(_gpu_pci_addr_for_vendor 10de)"
  [[ -n "$_igpu" && -n "$_nv" ]] || return 0
  printf '/dev/dri/by-path/pci-%s-card:/dev/dri/by-path/pci-%s-card\n' "$_igpu" "$_nv"
}

# Write the hybrid session env into <root>/etc/environment (idempotent; a prior
# arch-dotfiles block is replaced). No-op on non-hybrid GPUs. Call after the OS
# is installed but before the impermanence @blank snapshot.
gpu_write_session_env() {
  local _root="${1:-${MOUNT_ROOT:-/mnt}}"
  local _devs; _devs="$(gpu_hybrid_aq_drm_devices)"
  [[ -n "$_devs" ]] || return 0
  local _env="$_root/etc/environment"
  mkdir -p "$(dirname "$_env")"
  [[ -f "$_env" ]] \
    && sed -i '/# >>> arch-dotfiles gpu/,/# <<< arch-dotfiles gpu/d' "$_env"
  {
    echo '# >>> arch-dotfiles gpu (nvidia PRIME hybrid; see environment.sh)'
    echo "AQ_DRM_DEVICES=$_devs"
    echo '# <<< arch-dotfiles gpu'
  } >> "$_env"
}

# Derive audio packages from the resolved desktop array. PipeWire is installed
# whenever any desktop is selected.
# Sets AUDIO_PACKAGES (bash array) — idempotent, deduplicates on repeat calls.
_resolve_env_audio() {
  AUDIO_PACKAGES=()
  [[ ${#ENVIRONMENT_DESKTOP[@]} -eq 0 ]] && return 0
  local _pipewire=(pipewire pipewire-pulse pipewire-alsa wireplumber)
  AUDIO_PACKAGES=("${_pipewire[@]}")
}

# =============================================================================
# ENVIRONMENT VALIDATION
# =============================================================================
# Reads environment.desktop and environment.gpu from the Install Config,
# normalises each to a bash array, and validates values against the allowed
# sets. Sets ENVIRONMENT_DESKTOP and ENVIRONMENT_GPU globals.

_resolve_env_validate() {
  ENVIRONMENT_DESKTOP=()
  ENVIRONMENT_GPU=()

  # ── desktop ──────────────────────────────────────────────────────────────
  local _dt
  _dt="$(jsonc_strip "$CONFIG_FILE" \
    | jq -r '.environment.desktop | type // "null"')"
  case "$_dt" in
    string)
      mapfile -t ENVIRONMENT_DESKTOP < <(jsonc_strip "$CONFIG_FILE" \
        | jq -r '[.environment.desktop] | .[]')
      ;;
    array)
      mapfile -t ENVIRONMENT_DESKTOP < <(jsonc_strip "$CONFIG_FILE" \
        | jq -r '.environment.desktop[]?')
      ;;
    *) ;;
  esac

  for _de in "${ENVIRONMENT_DESKTOP[@]}"; do
    local _ok=false
    for _v in "${_VALID_DESKTOP[@]}"; do
      [[ "$_de" == "$_v" ]] && _ok=true && break
    done
    $_ok || error "Unknown desktop '${_de}'. Valid: ${_VALID_DESKTOP[*]}."
  done

  # ── gpu ──────────────────────────────────────────────────────────────────
  local _gt
  _gt="$(jsonc_strip "$CONFIG_FILE" \
    | jq -r '.environment.gpu | type // "null"')"
  case "$_gt" in
    string)
      mapfile -t ENVIRONMENT_GPU < <(jsonc_strip "$CONFIG_FILE" \
        | jq -r '[.environment.gpu] | .[]')
      ;;
    array)
      mapfile -t ENVIRONMENT_GPU < <(jsonc_strip "$CONFIG_FILE" \
        | jq -r '.environment.gpu[]?')
      ;;
    *) ;;
  esac

  for _gpu in "${ENVIRONMENT_GPU[@]}"; do
    local _ok=false
    for _v in "${_VALID_GPU[@]}"; do
      [[ "$_gpu" == "$_v" ]] && _ok=true && break
    done
    $_ok || error "Unknown GPU '${_gpu}'. Valid: ${_VALID_GPU[*]}."
  done
}

# =============================================================================
# PUBLIC ENTRY
# =============================================================================

# Single idempotent entry point. Resets the five resolved globals and re-runs
# the full pipeline (validate -> GPU -> audio). Safe to call repeatedly.
resolve_environment() {
  ENVIRONMENT_DESKTOP=()
  ENVIRONMENT_GPU=()
  GPU_PACMAN_PACKAGES=()
  GPU_PARU_PACKAGES=()
  AUDIO_PACKAGES=()
  _resolve_env_validate
  _resolve_env_gpu
  _resolve_env_audio
}

# =============================================================================
# SUMMARY
# =============================================================================

print_environment_summary() {
  local _desktop="${ENVIRONMENT_DESKTOP[*]:-none}"
  local _gpu="${ENVIRONMENT_GPU[*]:-none}"
  local _audio="none"
  [[ ${#ENVIRONMENT_DESKTOP[@]} -gt 0 ]] && _audio="pipewire"
  printf "    %-16s %s\n" "Desktop:" "$_desktop"
  printf "    %-16s %s\n" "GPU:" "$_gpu"
  printf "    %-16s %s\n" "Audio:" "$_audio"
}
