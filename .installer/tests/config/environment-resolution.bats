#!/usr/bin/env bats
# Tests for environment_resolve() in lib/config/environment.sh — the single public
# seam. Drives the module end-to-end with a fixture install.jsonc and asserts
# the five resolved globals populate. Stubs lspci so GPU "auto" is hermetic.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  jsonc_strip() { cat "$1"; }
  jsonc_read() { jsonc_strip "$1" | jq -r "$2"; }
  config_optional() { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  config_required() { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  section() { :; }
  warn()    { echo "WARN: $*" >&2; }
  confirm() { :; }

  # shellcheck source=../../lib/config/environment.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/environment.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  printf '%s\n' "$1" > "$CONFIG_FILE"
}

@test "environment_resolve populates all five globals from config" {
  write_config '{"environment": {"desktop": "kde", "gpu": "nvidia"}}'
  environment_resolve
  [ "${ENVIRONMENT_DESKTOP[0]}" = "kde" ]
  [ "${ENVIRONMENT_GPU[0]}" = "nvidia" ]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  [ "${#GPU_PARU_PACKAGES[@]}" -eq 0 ]
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire "* ]]
}

@test "environment_resolve accepts hyprland and derives audio" {
  write_config '{"environment": {"desktop": "hyprland", "gpu": "amd"}}'
  environment_resolve
  [ "${ENVIRONMENT_DESKTOP[0]}" = "hyprland" ]
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire "* ]]
}

@test "environment_resolve accepts niri and derives audio" {
  write_config '{"environment": {"desktop": "niri", "gpu": "amd"}}'
  environment_resolve
  [ "${ENVIRONMENT_DESKTOP[0]}" = "niri" ]
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire "* ]]
}

@test "environment_resolve accepts a kde+hyprland co-install" {
  write_config '{"environment": {"desktop": ["kde","hyprland"], "gpu": "amd"}}'
  environment_resolve
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 2 ]
  [ "${ENVIRONMENT_DESKTOP[1]}" = "hyprland" ]
}

# ── environment.stock (ADR 0112) ─────────────────────────────────────────────

@test "stock defaults to true and forces wayland_shell=none (ADR 0157)" {
  write_config '{"environment": {"desktop": "niri", "gpu": "amd"}}'
  environment_resolve
  [ "$ENVIRONMENT_STOCK" = "true" ]
  [ "$ENVIRONMENT_WAYLAND_SHELL" = "none" ]
}

@test "stock=false leaves wayland_shell at noctalia" {
  write_config \
    '{"environment": {"desktop": "niri", "gpu": "amd", "stock": false}}'
  environment_resolve
  [ "$ENVIRONMENT_STOCK" = "false" ]
  [ "$ENVIRONMENT_WAYLAND_SHELL" = "noctalia" ]
}

@test "stock=true resolves the flag and forces wayland_shell=none" {
  write_config \
    '{"environment": {"desktop": "niri", "gpu": "amd", "stock": true}}'
  environment_resolve
  [ "$ENVIRONMENT_STOCK" = "true" ]
  [ "$ENVIRONMENT_WAYLAND_SHELL" = "none" ]
}

@test "stock=true overrides an explicit wayland_shell=noctalia" {
  write_config '{"environment": {"desktop": "hyprland", "gpu": "amd",
    "stock": true, "wayland_shell": "noctalia"}}'
  environment_resolve
  [ "$ENVIRONMENT_WAYLAND_SHELL" = "none" ]
}

@test "environment_resolve is idempotent: second call produces identical state" {
  write_config '{"environment": {"desktop": "kde", "gpu": "nvidia"}}'
  environment_resolve
  local first_desktops="${ENVIRONMENT_DESKTOP[*]}"
  local first_gpus="${ENVIRONMENT_GPU[*]}"
  local gp1="${GPU_PACMAN_PACKAGES[*]}"
  local gr1="${GPU_PARU_PACKAGES[*]}"
  local first_audio="${AUDIO_PACKAGES[*]}"
  environment_resolve
  [ "${ENVIRONMENT_DESKTOP[*]}" = "$first_desktops" ]
  [ "${ENVIRONMENT_GPU[*]}" = "$first_gpus" ]
  [ "${GPU_PACMAN_PACKAGES[*]}" = "$gp1" ]
  [ "${GPU_PARU_PACKAGES[*]}" = "$gr1" ]
  [ "${AUDIO_PACKAGES[*]}" = "$first_audio" ]
}

@test "display_manager auto resolves to sddm when kde present (with hyprland)" {
  write_config \
    '{"environment": {"desktop": ["kde","hyprland"], "gpu": "amd"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "sddm" ]
}

@test "display_manager auto resolves to greetd for a hyprland-only box" {
  write_config '{"environment": {"desktop": "hyprland", "gpu": "amd"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "greetd" ]
}

@test "display_manager auto resolves to greetd for a niri-only box" {
  write_config '{"environment": {"desktop": "niri", "gpu": "amd"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "greetd" ]
}

@test "display_manager auto resolves to greetd for a hyprland+niri box" {
  write_config '{"environment": {"desktop": ["hyprland","niri"], "gpu": "amd"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "greetd" ]
}

@test "display_manager auto resolves to sddm for a kde+niri box" {
  write_config '{"environment": {"desktop": ["kde","niri"], "gpu": "amd"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "sddm" ]
}

@test "explicit greetd is honored on a hyprland box" {
  write_config \
    '{"environment": {"desktop": ["kde","hyprland"], "display_manager": "greetd"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "greetd" ]
}

@test "display_manager auto resolves to sddm for a kde-only install" {
  write_config '{"environment": {"desktop": "kde", "gpu": "amd"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "sddm" ]
}

@test "display_manager auto resolves to none when no desktop is selected" {
  write_config '{"environment": {"desktop": null, "gpu": "amd"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "none" ]
}

@test "explicit sddm passes through on a hyprland box" {
  write_config \
    '{"environment": {"desktop": "hyprland", "display_manager": "sddm"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "sddm" ]
}

@test "explicit greetd passes through on a kde-only box" {
  write_config \
    '{"environment": {"desktop": "kde", "display_manager": "greetd"}}'
  environment_resolve
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "greetd" ]
}

@test "concrete display_manager with no desktop aborts" {
  write_config \
    '{"environment": {"desktop": null, "display_manager": "sddm"}}'
  run environment_resolve
  [ "$status" -ne 0 ]
  [[ "$output" =~ "desktop" ]]
}

@test "environment_resolve with gpu='auto' mutates ENVIRONMENT_GPU to detected vendors" {
  write_config '{"environment": {"desktop": null, "gpu": "auto"}}'
  _environment_gpu_lspci_output() {
    echo "00:02.0 VGA compatible controller [0300]: NVIDIA Corp [10de:1234]"
  }
  environment_resolve
  [ "${ENVIRONMENT_GPU[0]}" = "nvidia" ]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  environment_resolve
  [ "${ENVIRONMENT_GPU[0]}" = "nvidia" ]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
}
