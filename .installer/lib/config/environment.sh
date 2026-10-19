#!/usr/bin/env bash
# =============================================================================
# lib/config/environment.sh — Environment validation and hardware resolution
# =============================================================================
# Requires: lib/common.sh already sourced (provides error, warn, jsonc_strip,
#           and CONFIG_FILE global).
#
# Public API:
#   environment_resolve — idempotent; populates ENVIRONMENT_DESKTOP,
#                         ENVIRONMENT_GPU, GPU_PACMAN_PACKAGES,
#                         GPU_PARU_PACKAGES, AUDIO_PACKAGES from
#                         CONFIG_FILE.
#
# Used by: lib/config/lifecycle.sh.
# =============================================================================

# shellcheck source=./install-config.sh
declare -F install_config_stock >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/install-config.sh"

# ── RESOLVED GLOBALS ─────────────────────────────────────────────────────────
# Set by _environment_validate; consumed by _environment_resolve_gpu,
# _environment_resolve_audio, and package_list_collect.
# shellcheck disable=SC2034
ENVIRONMENT_DESKTOP=()
# shellcheck disable=SC2034
ENVIRONMENT_GPU=()

# Set by _environment_validate (raw authored value) then rewritten to the
# concrete greeter by _environment_resolve_display_manager; consumed by
# install_state_write. Scalar: greetd | sddm | none (auto resolves away).
# shellcheck disable=SC2034
ENVIRONMENT_DISPLAY_MANAGER=""

# The Noctalia work-shell preset selector (ADR 0090/0097): noctalia | none. Set
# by _environment_validate (default noctalia); meaningful for any wlroots
# compositor in the desktop set (niri and Hyprland). Crosses into the chroot as
# an env var (chroot.sh) and is read by the niri/Hyprland adapters — no
# install-state field, like ENVIRONMENT_DESKTOP.
# shellcheck disable=SC2034
ENVIRONMENT_WAYLAND_SHELL=""

# Stock (pure) selector (ADR 0112): install every selected desktop as upstream
# stock — KDE = plasma-meta shell only (no apps/seed), niri/Hyprland = bare
# compositor. Set by _environment_validate (default false); when true it forces
# ENVIRONMENT_WAYLAND_SHELL=none so the compositor adapters seed nothing with no
# adapter change. Crosses into the chroot (chroot.sh) and is read by the KDE
# adapter — no install-state field, like ENVIRONMENT_WAYLAND_SHELL.
# shellcheck disable=SC2034
ENVIRONMENT_STOCK=""

# Set by _environment_resolve_gpu; consumed by package_list_collect.
# Declared here so package_list_collect can detect unresolved state.
GPU_PACMAN_PACKAGES=()
GPU_PARU_PACKAGES=()

# Set by _environment_resolve_audio; consumed by package_list_collect.
AUDIO_PACKAGES=()

# ── VALID VALUE SETS ──────────────────────────────────────────────────────────
_VALID_DESKTOP=(kde hyprland niri)
_VALID_GPU=(amd nvidia intel auto)
_VALID_DISPLAY_MANAGER=(auto greetd noctalia-greeter sddm)
_VALID_WAYLAND_SHELL=(noctalia none)

# The pure GPU + audio package maps, shared with the Package Resolver so the
# names live once. Detection and the intel refinement below stay impure here.
# shellcheck source=../packages/gpu.sh
declare -F gpu_vendor_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../packages/gpu.sh"
# shellcheck source=../packages/audio.sh
declare -F audio_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../packages/audio.sh"

# =============================================================================
# GPU RESOLUTION
# =============================================================================

# Wraps lspci -nn. Override in tests to control hardware detection.
_environment_gpu_lspci_output() { lspci -nn 2>/dev/null; }

# _environment_gpu_intel_refine — the intel pre-Broadwell downgrade, applied
# install-side only (the pure map returns the intel-media-driver default).
# Broadwell+ (device id ≥ 0x1600) keeps intel-media-driver; older gets
# libva-intel-driver; an unreadable id keeps the modern default. Needs lspci,
# so it lives here, not in the pure map.
_environment_gpu_intel_refine() {
  local device_id decimal_id
  device_id="$(_environment_gpu_lspci_output | awk '
    tolower($0) ~ /intel/ && match($0, /8086:[0-9a-fA-F]+/) {
      print substr($0, RSTART + 5, RLENGTH - 5); exit
    }')"
  if [[ -n "$device_id" ]]; then
    decimal_id=$(( 16#$device_id ))
    if (( decimal_id >= 0x1600 )); then echo "intel-media-driver"
    else echo "libva-intel-driver"; fi
  else
    echo "intel-media-driver"
  fi
}

# Detect GPU vendors from lspci output. Emits one vendor per line.
# Returns "vm" for recognised VM GPUs; nothing for unknown.
_environment_gpu_detect_vendors() {
  local lspci_output
  lspci_output="$(_environment_gpu_lspci_output)"
  local found=false

  if echo "$lspci_output" \
      | grep -qiP '15ad:|1af4:1050|VMware|Virtio GPU|VirtualBox'; then
    echo "vm"
    return
  fi

  echo "$lspci_output" | grep -qi '1002:'  && { echo "amd";    found=true; }
  echo "$lspci_output" | grep -qi '10de:'  && { echo "nvidia"; found=true; }
  echo "$lspci_output" | grep -qi '8086:'  && { echo "intel";  found=true; }

  if ! $found; then
    warn "GPU auto-detection: no recognised vendor in lspci output" \
         "— using mesa fallback."
    echo "vm"
  fi
}

# Translate ENVIRONMENT_GPU → GPU_PACMAN_PACKAGES + GPU_PARU_PACKAGES.
# If ENVIRONMENT_GPU=("auto"), runs lspci detection and updates ENVIRONMENT_GPU.
_environment_resolve_gpu() {
  GPU_PACMAN_PACKAGES=()
  GPU_PARU_PACKAGES=()

  if [[ "${#ENVIRONMENT_GPU[@]}" -eq 1 \
     && "${ENVIRONMENT_GPU[0]}" == "auto" ]]; then
    mapfile -t ENVIRONMENT_GPU < <(_environment_gpu_detect_vendors)
  fi

  local vendor vendor_packages
  for vendor in "${ENVIRONMENT_GPU[@]}"; do
    # The shared pure map gives the deterministic set; intel additionally gets
    # the lspci-driven pre-Broadwell refinement (install-side only).
    if [[ "$vendor" == intel ]]; then
      vendor_packages="$(_environment_gpu_intel_refine)"
    else
      vendor_packages="$(gpu_vendor_packages "$vendor")"
    fi
    # shellcheck disable=SC2206
    GPU_PACMAN_PACKAGES+=( $vendor_packages )
  done

  # An amd+nvidia (hybrid) result no longer pulls envycontrol: the runtime
  # switcher was installed but never invoked. The deterministic hybrid config
  # is now owned by the chroot GPU Configuration Module (ADR 0053), so the
  # resolved vendor list is threaded to the chroot via install-state instead.
}

# Derive audio packages from the resolved desktop array. PipeWire is installed
# whenever any desktop is selected.
# Sets AUDIO_PACKAGES (bash array) — idempotent, deduplicates on repeat calls.
_environment_resolve_audio() {
  AUDIO_PACKAGES=()
  [[ ${#ENVIRONMENT_DESKTOP[@]} -eq 0 ]] && return 0
  # The PipeWire stack — the name list lives in the shared pure audio map so the
  # Package Resolver reports exactly what installs here (R11).
  mapfile -t AUDIO_PACKAGES < <(audio_packages)
}

# =============================================================================
# ENVIRONMENT VALIDATION
# =============================================================================
# Reads environment.desktop and environment.gpu from the Install Config,
# normalises each to a bash array, and validates values against the allowed
# sets. Sets ENVIRONMENT_DESKTOP and ENVIRONMENT_GPU globals.

_environment_validate() {
  ENVIRONMENT_DESKTOP=()
  ENVIRONMENT_GPU=()

  local desktop gpu
  mapfile -t ENVIRONMENT_DESKTOP < <(_environment_read_list desktop)
  for desktop in "${ENVIRONMENT_DESKTOP[@]}"; do
    _environment_is_one_of "$desktop" "${_VALID_DESKTOP[@]}" \
      || error "Unknown desktop '${desktop}'. Valid: ${_VALID_DESKTOP[*]}."
  done

  mapfile -t ENVIRONMENT_GPU < <(_environment_read_list gpu)
  for gpu in "${ENVIRONMENT_GPU[@]}"; do
    _environment_is_one_of "$gpu" "${_VALID_GPU[@]}" \
      || error "Unknown GPU '${gpu}'. Valid: ${_VALID_GPU[*]}."
  done

  # Display manager: scalar discriminator; defaults to `auto`. The concrete
  # greeter is derived from the desktop set later by
  # _environment_resolve_display_manager (ADR 0069).
  ENVIRONMENT_DISPLAY_MANAGER="$(install_config_display_manager)"
  _environment_is_one_of "$ENVIRONMENT_DISPLAY_MANAGER" \
      "${_VALID_DISPLAY_MANAGER[@]}" \
    || error "Unknown display_manager '${ENVIRONMENT_DISPLAY_MANAGER}'." \
      "Valid: ${_VALID_DISPLAY_MANAGER[*]}."

  # Wayland shell: the Noctalia work-shell preset selector (ADR 0090/0097);
  # defaults to noctalia. Meaningful for any wlroots compositor in the desktop
  # set (niri and Hyprland) — harmless otherwise (the niri/Hyprland adapters
  # are the readers).
  ENVIRONMENT_WAYLAND_SHELL="$(install_config_wayland_shell)"
  _environment_is_one_of "$ENVIRONMENT_WAYLAND_SHELL" \
      "${_VALID_WAYLAND_SHELL[@]}" \
    || error "Unknown wayland_shell '${ENVIRONMENT_WAYLAND_SHELL}'." \
      "Valid: ${_VALID_WAYLAND_SHELL[*]}."

  _environment_validate_stock
}

# Stock (pure): bool selector for an upstream-stock install (ADR 0112). When
# true it is authoritative for every selected desktop and forces
# wayland_shell=none, so the niri/Hyprland adapters seed nothing (their
# existing `none` path) with no adapter change; the KDE adapter reads
# ENVIRONMENT_STOCK directly.
_environment_validate_stock() {
  ENVIRONMENT_STOCK="$(install_config_stock)"
  [[ "$ENVIRONMENT_STOCK" == true || "$ENVIRONMENT_STOCK" == false ]] \
    || error "Invalid environment.stock '${ENVIRONMENT_STOCK}' — want a bool."
  if [[ "$ENVIRONMENT_STOCK" == true ]]; then
    ENVIRONMENT_WAYLAND_SHELL="none"
  fi
}

# _environment_read_list <key> — environment.<key> one entry per line, whether
# authored as a string or an array; nothing otherwise.
_environment_read_list() {
  local key="$1" key_type
  key_type="$(jsonc_strip "$CONFIG_FILE" \
    | jq -r ".environment.${key} | type // \"null\"")"
  case "$key_type" in
    string)
      jsonc_strip "$CONFIG_FILE" | jq -r "[.environment.${key}] | .[]" ;;
    array)
      jsonc_strip "$CONFIG_FILE" | jq -r ".environment.${key}[]?" ;;
  esac
}

# _environment_is_one_of <value> <allowed…> — rc 0 when <value> is allowed.
_environment_is_one_of() {
  local value="$1" allowed
  shift
  for allowed in "$@"; do
    [[ "$value" == "$allowed" ]] && return 0
  done
  return 1
}

# Resolve ENVIRONMENT_DISPLAY_MANAGER (auto|greetd|noctalia-greeter|sddm)
# into the concrete greeter the chroot dispatches (ADR 0069). `auto` is
# DESKTOP-AWARE (ADR 0091): `greetd` for a KDE-free non-empty desktop set
# (hyprland and/or niri), `sddm` when the set contains `kde`, and `none` when no
# desktop is selected. It is a smart default, not a lock — seatd (ADR 0068) lets
# any greeter launch any DE, so an explicit greeter (noctalia-greeter included,
# ADR 0158) still passes through unchanged. A concrete
# greeter with no desktop aborts — a greeter with no session to launch. Requires
# ENVIRONMENT_DESKTOP already resolved by _environment_validate.
_environment_resolve_display_manager() {
  local authored="${ENVIRONMENT_DISPLAY_MANAGER:-auto}"
  if [[ ${#ENVIRONMENT_DESKTOP[@]} -eq 0 ]]; then
    if [[ "$authored" == "auto" ]]; then
      ENVIRONMENT_DISPLAY_MANAGER="none"
      return 0
    fi
    error "display_manager '${authored}' selected but no desktop is set —" \
      "a greeter has no session to launch."
  fi
  if [[ "$authored" == "auto" ]]; then
    ENVIRONMENT_DISPLAY_MANAGER="greetd"
    _environment_is_one_of kde "${ENVIRONMENT_DESKTOP[@]}" \
      && ENVIRONMENT_DISPLAY_MANAGER="sddm"
  fi
  return 0
}

# =============================================================================
# PUBLIC ENTRY
# =============================================================================

# Single idempotent entry point. Resets the five resolved globals and re-runs
# the full pipeline (validate -> GPU -> audio). Safe to call repeatedly.
environment_resolve() {
  ENVIRONMENT_DESKTOP=()
  ENVIRONMENT_GPU=()
  ENVIRONMENT_DISPLAY_MANAGER=""
  ENVIRONMENT_WAYLAND_SHELL=""
  ENVIRONMENT_STOCK=""
  GPU_PACMAN_PACKAGES=()
  # shellcheck disable=SC2034 # consumed by the Runner's paru pass
  GPU_PARU_PACKAGES=()
  # shellcheck disable=SC2034 # consumed by package_list_collect
  AUDIO_PACKAGES=()
  _environment_validate
  _environment_resolve_display_manager
  _environment_resolve_gpu
  _environment_resolve_audio
}

# =============================================================================
# SUMMARY
# =============================================================================

# _environment_summary_labels <token>... → the tokens rendered as ", "-joined
# Display Labels (KDE, AMD, NVIDIA, …), so the review reads consistently with
# the menu. Display only — never touches the ENVIRONMENT_* values used to
# select packages.
_environment_summary_labels() {
  declare -F display_label >/dev/null 2>&1 \
    || source "${BASH_SOURCE[0]%/*}/display.sh"
  local labels="" token
  for token in "$@"; do labels+="${labels:+, }$(display_label "$token")"; done
  printf '%s' "$labels"
}

environment_print_summary() {
  local desktop_labels gpu_labels audio="none"
  desktop_labels="$([[ ${#ENVIRONMENT_DESKTOP[@]} -gt 0 ]] \
    && _environment_summary_labels "${ENVIRONMENT_DESKTOP[@]}" || echo none)"
  gpu_labels="$([[ ${#ENVIRONMENT_GPU[@]} -gt 0 ]] \
    && _environment_summary_labels "${ENVIRONMENT_GPU[@]}" || echo none)"
  [[ ${#ENVIRONMENT_DESKTOP[@]} -gt 0 ]] && audio="pipewire"
  printf "    %-16s %s\n" "Desktop:" "$desktop_labels"
  printf "    %-16s %s\n" "GPU:" "$gpu_labels"
  printf "    %-16s %s\n" "Audio:" "$audio"
}
