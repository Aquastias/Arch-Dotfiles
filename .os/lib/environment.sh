#!/usr/bin/env bash
# =============================================================================
# lib/environment.sh — Environment validation and hardware resolution
# =============================================================================
# Sourced by lib/config.sh.
# Requires: lib/common.sh already sourced (provides error, warn, jsonc_strip,
#           and CONFIG_FILE global).
#
# Public API (three separate calls, in order):
#   validate_environment   — reads CONFIG_FILE; sets ENVIRONMENT_DESKTOP/GPU
#   resolve_gpu_packages   — ENVIRONMENT_GPU  → GPU_PACMAN_PACKAGES + GPU_PARU_PACKAGES
#   resolve_audio_packages — ENVIRONMENT_DESKTOP → AUDIO_PACKAGES
#
# Pipeline contract
# ─────────────────
# validate_config() (lib/config.sh) calls all three in order. Callers that
# use GPU_PACMAN_PACKAGES, GPU_PARU_PACKAGES, or AUDIO_PACKAGES must call
# validate_config() first — collect_packages() in lib/packages.sh enforces this.
# =============================================================================

# ── RESOLVED GLOBALS ─────────────────────────────────────────────────────────
# Set by validate_environment; consumed by resolve_gpu_packages,
# resolve_audio_packages, and collect_packages.
# shellcheck disable=SC2034
ENVIRONMENT_DESKTOP=()
# shellcheck disable=SC2034
ENVIRONMENT_GPU=()

# Set by resolve_gpu_packages; consumed by collect_packages.
# Declared here so collect_packages can detect unresolved state.
GPU_PACMAN_PACKAGES=()
GPU_PARU_PACKAGES=()

# Set by resolve_audio_packages; consumed by collect_packages.
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
    amd)    echo "vulkan-radeon xf86-video-amdgpu mesa libva-mesa-driver" ;;
    nvidia) echo "nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver egl-wayland" ;;
    intel)
      local lspci_out device_id dec_id
      lspci_out="$(_gpu_lspci_output)"
      device_id="$(echo "$lspci_out" | grep -i "intel" | grep -oP '8086:\K[0-9a-fA-F]+' | head -1)"
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

  if echo "$lspci_out" | grep -qiP '15ad:|1af4:1050|VMware|Virtio GPU|VirtualBox'; then
    echo "vm"
    return
  fi

  echo "$lspci_out" | grep -qi '1002:'  && { echo "amd";    found=true; }
  echo "$lspci_out" | grep -qi '10de:'  && { echo "nvidia"; found=true; }
  echo "$lspci_out" | grep -qi '8086:'  && { echo "intel";  found=true; }

  if ! $found; then
    warn "GPU auto-detection: no recognised vendor found in lspci output — using mesa fallback."
    echo "vm"
  fi
}

# Translate ENVIRONMENT_GPU → GPU_PACMAN_PACKAGES + GPU_PARU_PACKAGES.
# If ENVIRONMENT_GPU=("auto"), runs lspci detection and updates ENVIRONMENT_GPU.
resolve_gpu_packages() {
  GPU_PACMAN_PACKAGES=()
  GPU_PARU_PACKAGES=()

  if [[ "${#ENVIRONMENT_GPU[@]}" -eq 1 && "${ENVIRONMENT_GPU[0]}" == "auto" ]]; then
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
  [[ "$_has_amd" == "true" && "$_has_nvidia" == "true" ]] && GPU_PARU_PACKAGES+=( envycontrol ) || true
}

# Derive audio packages from the resolved desktop array. PipeWire is installed
# whenever any desktop is selected.
# Sets AUDIO_PACKAGES (bash array) — idempotent, deduplicates on repeat calls.
resolve_audio_packages() {
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

validate_environment() {
  ENVIRONMENT_DESKTOP=()
  ENVIRONMENT_GPU=()

  # ── desktop ──────────────────────────────────────────────────────────────
  local _dt
  _dt="$(jsonc_strip "$CONFIG_FILE" | jq -r '.environment.desktop | type // "null"')"
  case "$_dt" in
    string)
      mapfile -t ENVIRONMENT_DESKTOP < <(jsonc_strip "$CONFIG_FILE" | jq -r '[.environment.desktop] | .[]')
      ;;
    array)
      mapfile -t ENVIRONMENT_DESKTOP < <(jsonc_strip "$CONFIG_FILE" | jq -r '.environment.desktop[]?')
      ;;
    *) ;;
  esac

  for _de in "${ENVIRONMENT_DESKTOP[@]}"; do
    local _ok=false
    for _v in "${_VALID_DESKTOP[@]}"; do [[ "$_de" == "$_v" ]] && _ok=true && break; done
    $_ok || error "Unknown desktop '${_de}'. Valid: ${_VALID_DESKTOP[*]}."
  done

  # ── gpu ──────────────────────────────────────────────────────────────────
  local _gt
  _gt="$(jsonc_strip "$CONFIG_FILE" | jq -r '.environment.gpu | type // "null"')"
  case "$_gt" in
    string)
      mapfile -t ENVIRONMENT_GPU < <(jsonc_strip "$CONFIG_FILE" | jq -r '[.environment.gpu] | .[]')
      ;;
    array)
      mapfile -t ENVIRONMENT_GPU < <(jsonc_strip "$CONFIG_FILE" | jq -r '.environment.gpu[]?')
      ;;
    *) ;;
  esac

  for _gpu in "${ENVIRONMENT_GPU[@]}"; do
    local _ok=false
    for _v in "${_VALID_GPU[@]}"; do [[ "$_gpu" == "$_v" ]] && _ok=true && break; done
    $_ok || error "Unknown GPU '${_gpu}'. Valid: ${_VALID_GPU[*]}."
  done
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
