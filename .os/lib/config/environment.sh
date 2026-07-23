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
# the nvidia dGPU is powered OFF on-demand and only used for per-app offload
# (prime-run/gamemode). The Wayland compositor must therefore scan out on the
# iGPU — Hyprland/aquamarine otherwise picks the first DRM device (often nvidia)
# and renders to a display the panel can't show, OR tries to open the powered-off
# dGPU and crashes → black screen / bounce to the DM (KDE/KWin negotiates this
# itself; Hyprland does not). AQ_DRM_DEVICES=<igpu> pins the compositor to the
# panel's GPU. It lists the iGPU ONLY: including the dGPU makes aquamarine open
# the powered-off nvidia node and fail; nvidia offload is per-app (DRI_PRIME /
# prime-run), independent of the compositor's device list.
#
# TWO traps this avoids (both hit during bring-up):
#  1. AQ_DRM_DEVICES is COLON-separated, and PCI `by-path` node names contain
#     colons (…/pci-0000:34:00.0-card) → aquamarine splits them into garbage and
#     reports "Found no gpus to use". `/dev/dri/cardN` has no colon but the number
#     is not stable across boots. So we ship a udev rule that creates colon-free,
#     vendor-stable symlinks (/dev/dri/aq-igpu, /dev/dri/aq-dgpu) and point
#     AQ_DRM_DEVICES at the iGPU one.
#  2. ONLY AQ_DRM_DEVICES is written (Hyprland/aquamarine-specific, inert to
#     everything else). Do NOT set global LIBVA_DRIVER_NAME / __GLX_VENDOR_LIBRARY
#     _NAME / NVD_BACKEND — those force the offload (nvidia) driver on EVERY GL/VA
#     client incl. the SDDM greeter + KDE on the iGPU panel → blank grey greeter.
#
# The udev rule lands in /usr/lib (never a Rollback Dataset) and AQ_DRM_DEVICES in
# /etc/environment before the @blank snapshot, so both survive impermanence.

# True when the resolved GPU set is an nvidia + integrated (amd/intel) hybrid.
gpu_is_nvidia_hybrid() {
  local _has_nv=false _has_igpu=false _v
  for _v in "${ENVIRONMENT_GPU[@]:-}"; do
    [[ "$_v" == nvidia ]]              && _has_nv=true
    [[ "$_v" == amd || "$_v" == intel ]] && _has_igpu=true
  done
  [[ "$_has_nv" == true && "$_has_igpu" == true ]]
}

# Emit the udev rule that maps each GPU (by PCI vendor) to a stable, colon-free
# DRM card symlink. 0x1002 amd, 0x8086 intel, 0x10de nvidia. Pure string.
gpu_aq_udev_rule() {
  cat <<'RULES'
# Stable, colon-free DRM card symlinks for AQ_DRM_DEVICES (Hyprland/aquamarine).
# AQ_DRM_DEVICES splits on ':'; PCI by-path names contain ':' and cardN numbers
# aren't stable across boots — resolve by PCI vendor instead. Managed by the Arch
# installer (lib/config/environment.sh).
KERNEL=="card[0-9]*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x1002", SYMLINK+="dri/aq-igpu"
KERNEL=="card[0-9]*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x8086", SYMLINK+="dri/aq-igpu"
KERNEL=="card[0-9]*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x10de", SYMLINK+="dri/aq-dgpu"
RULES
}

# Write the udev rule (/usr/lib) + AQ_DRM_DEVICES (/etc/environment) under <root>
# when the GPU is an nvidia+integrated hybrid. Idempotent (a prior arch-dotfiles
# block is replaced). No-op otherwise. Call after the OS is installed but before
# the impermanence @blank snapshot.
gpu_write_session_env() {
  local _root="${1:-${MOUNT_ROOT:-/mnt}}"
  gpu_is_nvidia_hybrid || return 0
  local _rule="$_root/usr/lib/udev/rules.d/60-aq-drm-devices.rules"
  mkdir -p "$(dirname "$_rule")"
  gpu_aq_udev_rule > "$_rule"
  local _env="$_root/etc/environment"
  mkdir -p "$(dirname "$_env")"
  [[ -f "$_env" ]] \
    && sed -i '/# >>> arch-dotfiles gpu/,/# <<< arch-dotfiles gpu/d' "$_env"
  {
    echo '# >>> arch-dotfiles gpu (nvidia PRIME hybrid; see environment.sh)'
    echo '# Compositor on the iGPU only — the dGPU is off/on-demand; per-app'
    echo '# nvidia offload is via prime-run, not this list.'
    echo 'AQ_DRM_DEVICES=/dev/dri/aq-igpu'
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

# _env_summary_labels <token>... → the tokens rendered as ", "-joined Display
# Labels (KDE, AMD, NVIDIA, …), so the review reads consistently with the menu.
# Display only — never touches the ENVIRONMENT_* values used to select packages.
_env_summary_labels() {
  [[ "$(type -t display_label)" == "function" ]] \
    || source "${BASH_SOURCE[0]%/*}/display.sh"
  local out="" t
  for t in "$@"; do out+="${out:+, }$(display_label "$t")"; done
  printf '%s' "$out"
}

print_environment_summary() {
  local _desktop _gpu
  _desktop="$([[ ${#ENVIRONMENT_DESKTOP[@]} -gt 0 ]] \
    && _env_summary_labels "${ENVIRONMENT_DESKTOP[@]}" || echo none)"
  _gpu="$([[ ${#ENVIRONMENT_GPU[@]} -gt 0 ]] \
    && _env_summary_labels "${ENVIRONMENT_GPU[@]}" || echo none)"
  local _audio="none"
  [[ ${#ENVIRONMENT_DESKTOP[@]} -gt 0 ]] && _audio="pipewire"
  printf "    %-16s %s\n" "Desktop:" "$_desktop"
  printf "    %-16s %s\n" "GPU:" "$_gpu"
  printf "    %-16s %s\n" "Audio:" "$_audio"
}
