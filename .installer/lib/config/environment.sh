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

# Set by _resolve_env_validate (raw authored value) then rewritten to the
# concrete greeter by _resolve_env_display_manager; consumed by
# install_state_write. Scalar: greetd | sddm | none (auto resolves away).
# shellcheck disable=SC2034
ENVIRONMENT_DISPLAY_MANAGER=""

# The Noctalia work-shell preset selector (ADR 0090): noctalia | none. Set by
# _resolve_env_validate (default noctalia); meaningful only when niri is in the
# desktop set. Crosses into the chroot as an env var (chroot.sh) and is read by
# the niri adapter — no install-state field, like ENVIRONMENT_DESKTOP.
# shellcheck disable=SC2034
ENVIRONMENT_NIRI_SHELL=""

# Set by _resolve_env_gpu; consumed by collect_packages.
# Declared here so collect_packages can detect unresolved state.
GPU_PACMAN_PACKAGES=()
GPU_PARU_PACKAGES=()

# Set by _resolve_env_audio; consumed by collect_packages.
AUDIO_PACKAGES=()

# ── VALID VALUE SETS ──────────────────────────────────────────────────────────
_VALID_DESKTOP=(kde hyprland niri)
_VALID_GPU=(amd nvidia intel auto)
_VALID_DISPLAY_MANAGER=(auto greetd sddm)
_VALID_NIRI_SHELL=(noctalia none)

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
_gpu_lspci_output() { lspci -nn 2>/dev/null; }

# _gpu_intel_refine — the intel pre-Broadwell downgrade, applied install-side
# only (the pure map returns the intel-media-driver default). Broadwell+
# (device id ≥ 0x1600) keeps intel-media-driver; older gets libva-intel-driver;
# an unreadable id keeps the modern default. Needs lspci, so it lives here, not
# in the pure map.
_gpu_intel_refine() {
  local lspci_out device_id dec_id
  lspci_out="$(_gpu_lspci_output)"
  device_id="$(echo "$lspci_out" | grep -i "intel" \
    | grep -oP '8086:\K[0-9a-fA-F]+' | head -1)"
  if [[ -n "$device_id" ]]; then
    dec_id=$(( 16#$device_id ))
    if (( dec_id >= 0x1600 )); then echo "intel-media-driver"
    else echo "libva-intel-driver"; fi
  else
    echo "intel-media-driver"
  fi
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
    # The shared pure map gives the deterministic set; intel additionally gets
    # the lspci-driven pre-Broadwell refinement (install-side only).
    if [[ "$_vendor" == intel ]]; then
      _pkgs="$(_gpu_intel_refine)"
    else
      _pkgs="$(gpu_vendor_packages "$_vendor")"
    fi
    # shellcheck disable=SC2206
    GPU_PACMAN_PACKAGES+=( $_pkgs )
  done

  # An amd+nvidia (hybrid) result no longer pulls envycontrol: the runtime
  # switcher was installed but never invoked. The deterministic hybrid config
  # is now owned by the chroot GPU Configuration Module (ADR 0053), so the
  # resolved vendor list is threaded to the chroot via install-state instead.
}

# Derive audio packages from the resolved desktop array. PipeWire is installed
# whenever any desktop is selected.
# Sets AUDIO_PACKAGES (bash array) — idempotent, deduplicates on repeat calls.
_resolve_env_audio() {
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

  # ── display manager ────────────────────────────────────────────────────────
  # Scalar discriminator; defaults to `auto`. The concrete greeter is derived
  # from the desktop set later by _resolve_env_display_manager (ADR 0069).
  ENVIRONMENT_DISPLAY_MANAGER="$(jsonc_strip "$CONFIG_FILE" \
    | jq -r '.environment.display_manager // "auto"')"
  local _dm_ok=false
  for _v in "${_VALID_DISPLAY_MANAGER[@]}"; do
    [[ "$ENVIRONMENT_DISPLAY_MANAGER" == "$_v" ]] && _dm_ok=true && break
  done
  $_dm_ok || error "Unknown display_manager '${ENVIRONMENT_DISPLAY_MANAGER}'." \
    "Valid: ${_VALID_DISPLAY_MANAGER[*]}."

  # ── niri shell ─────────────────────────────────────────────────────────────
  # The Noctalia work-shell preset selector (ADR 0090); defaults to noctalia.
  # Meaningful only when niri is in the desktop set — harmless otherwise (the
  # niri adapter is the only reader).
  ENVIRONMENT_NIRI_SHELL="$(jsonc_strip "$CONFIG_FILE" \
    | jq -r '.environment.niri_shell // "noctalia"')"
  local _ns_ok=false
  for _v in "${_VALID_NIRI_SHELL[@]}"; do
    [[ "$ENVIRONMENT_NIRI_SHELL" == "$_v" ]] && _ns_ok=true && break
  done
  $_ns_ok || error "Unknown niri_shell '${ENVIRONMENT_NIRI_SHELL}'." \
    "Valid: ${_VALID_NIRI_SHELL[*]}."
}

# Resolve ENVIRONMENT_DISPLAY_MANAGER (`auto`|`greetd`|`sddm`) into the concrete
# greeter the chroot dispatches (ADR 0069). `auto` is DESKTOP-AWARE (ADR 0091):
# `greetd` for a KDE-free non-empty desktop set (hyprland and/or niri), `sddm`
# when the set contains `kde`, and `none` when no desktop is selected. It is a
# smart default, not a lock — seatd (ADR 0068) lets any greeter launch any DE,
# so an explicit `greetd`/`sddm` still passes through unchanged. A concrete
# greeter with no desktop aborts — a greeter with no session to launch. Requires
# ENVIRONMENT_DESKTOP already resolved by _resolve_env_validate.
_resolve_env_display_manager() {
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
    local _has_kde=false _d
    for _d in "${ENVIRONMENT_DESKTOP[@]}"; do
      [[ "$_d" == kde ]] && { _has_kde=true; break; }
    done
    if $_has_kde; then
      ENVIRONMENT_DISPLAY_MANAGER="sddm"
    else
      ENVIRONMENT_DISPLAY_MANAGER="greetd"
    fi
  fi
}

# =============================================================================
# PUBLIC ENTRY
# =============================================================================

# Single idempotent entry point. Resets the five resolved globals and re-runs
# the full pipeline (validate -> GPU -> audio). Safe to call repeatedly.
resolve_environment() {
  ENVIRONMENT_DESKTOP=()
  ENVIRONMENT_GPU=()
  ENVIRONMENT_DISPLAY_MANAGER=""
  ENVIRONMENT_NIRI_SHELL=""
  GPU_PACMAN_PACKAGES=()
  GPU_PARU_PACKAGES=()
  AUDIO_PACKAGES=()
  _resolve_env_validate
  _resolve_env_display_manager
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
  declare -F display_label >/dev/null 2>&1 \
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
