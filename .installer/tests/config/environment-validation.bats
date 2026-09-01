#!/usr/bin/env bats
# Tests for _resolve_env_validate() in lib/config/lifecycle.sh.
#
# Strategy: stub common.sh helpers (cfgo, jsonc, error, info, section, warn)
# so the module can be sourced without a live system. Happy-path tests call
# _resolve_env_validate() directly and assert globals. Error-path tests use
# `run` so error() exits the subshell rather than the test process.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  # ── common.sh stubs ────────────────────────────────────────────────────────
  jsonc_strip() { cat "$1"; }
  cfgo()    { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()     { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  section() { :; }
  warn()    { :; }
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

# ── desktop valid values ───────────────────────────────────────────────────

@test "desktop 'kde' passes validation and sets ENVIRONMENT_DESKTOP" {
  write_config '{"environment": {"desktop": "kde", "gpu": "auto"}}'
  _resolve_env_validate
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 1 ]
  [ "${ENVIRONMENT_DESKTOP[0]}" = "kde" ]
}

@test "desktop array ['kde'] passes and sets a one-element array" {
  write_config \
    '{"environment": {"desktop": ["kde"], "gpu": "auto"}}'
  _resolve_env_validate
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 1 ]
  [ "${ENVIRONMENT_DESKTOP[0]}" = "kde" ]
}

@test "desktop 'hyprland' passes validation and sets ENVIRONMENT_DESKTOP" {
  write_config '{"environment": {"desktop": "hyprland", "gpu": "auto"}}'
  _resolve_env_validate
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 1 ]
  [ "${ENVIRONMENT_DESKTOP[0]}" = "hyprland" ]
}

@test "desktop 'niri' passes validation and sets ENVIRONMENT_DESKTOP" {
  write_config '{"environment": {"desktop": "niri", "gpu": "auto"}}'
  _resolve_env_validate
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 1 ]
  [ "${ENVIRONMENT_DESKTOP[0]}" = "niri" ]
}

@test "desktop array ['kde','hyprland','niri'] passes and sets three elements" {
  write_config \
    '{"environment": {"desktop": ["kde","hyprland","niri"], "gpu": "auto"}}'
  _resolve_env_validate
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 3 ]
  [ "${ENVIRONMENT_DESKTOP[2]}" = "niri" ]
}

@test "desktop array ['kde','hyprland'] passes and sets two elements" {
  write_config \
    '{"environment": {"desktop": ["kde", "hyprland"], "gpu": "auto"}}'
  _resolve_env_validate
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 2 ]
  [ "${ENVIRONMENT_DESKTOP[0]}" = "kde" ]
  [ "${ENVIRONMENT_DESKTOP[1]}" = "hyprland" ]
}

@test "desktop array with an unknown value fails validation" {
  write_config \
    '{"environment": {"desktop": ["kde", "sway"], "gpu": "auto"}}'
  run _resolve_env_validate
  [ "$status" -ne 0 ]
  [[ "$output" =~ "sway" ]]
}

@test "desktop null passes validation and gives empty array" {
  write_config '{"environment": {"desktop": null, "gpu": "auto"}}'
  _resolve_env_validate
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 0 ]
}

@test "environment key missing entirely passes validation" {
  write_config '{"mode": "single", "disk": "/dev/sda"}'
  _resolve_env_validate
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 0 ]
}

@test "desktop 'gnome' fails validation with error naming valid options" {
  write_config '{"environment": {"desktop": "gnome", "gpu": "auto"}}'
  run _resolve_env_validate
  [ "$status" -ne 0 ]
  [[ "$output" =~ "kde" ]]
}

@test "gpu 'auto' passes validation" {
  write_config '{"environment": {"desktop": null, "gpu": "auto"}}'
  _resolve_env_validate
  [ "${ENVIRONMENT_GPU[0]}" = "auto" ]
}

@test "gpu 'amd', 'nvidia', 'intel' each pass validation" {
  for vendor in amd nvidia intel; do
    write_config \
      "{\"environment\": {\"desktop\": null, \"gpu\": \"${vendor}\"}}"
    _resolve_env_validate
    [ "${ENVIRONMENT_GPU[0]}" = "$vendor" ]
  done
}

@test "gpu array ['amd','nvidia'] passes and sets two-element array" {
  write_config '{"environment": {"desktop": null, "gpu": ["amd", "nvidia"]}}'
  _resolve_env_validate
  [ "${#ENVIRONMENT_GPU[@]}" -eq 2 ]
  [ "${ENVIRONMENT_GPU[0]}" = "amd" ]
  [ "${ENVIRONMENT_GPU[1]}" = "nvidia" ]
}

@test "gpu 'vulkan' fails validation with error naming valid options" {
  write_config '{"environment": {"desktop": null, "gpu": "vulkan"}}'
  run _resolve_env_validate
  [ "$status" -ne 0 ]
  [[ "$output" =~ "amd" ]]
  [[ "$output" =~ "nvidia" ]]
}

# ── display manager valid values ───────────────────────────────────────────

@test "display_manager 'sddm' passes validation" {
  write_config \
    '{"environment": {"desktop": "kde", "display_manager": "sddm"}}'
  _resolve_env_validate
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "sddm" ]
}

@test "display_manager 'greetd' passes validation" {
  write_config \
    '{"environment": {"desktop": "hyprland", "display_manager": "greetd"}}'
  _resolve_env_validate
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "greetd" ]
}

@test "display_manager defaults to 'auto' when absent" {
  write_config '{"environment": {"desktop": "kde"}}'
  _resolve_env_validate
  [ "$ENVIRONMENT_DISPLAY_MANAGER" = "auto" ]
}

@test "display_manager unknown value fails validation naming valid options" {
  write_config \
    '{"environment": {"desktop": "kde", "display_manager": "lightdm"}}'
  run _resolve_env_validate
  [ "$status" -ne 0 ]
  [[ "$output" =~ "lightdm" ]]
  [[ "$output" =~ "greetd" ]]
}

# ── wayland shell preset (ADR 0090/0097) ────────────────────────────────────

@test "wayland_shell defaults to noctalia when absent" {
  write_config '{"environment": {"desktop": "niri"}}'
  _resolve_env_validate
  [ "$ENVIRONMENT_WAYLAND_SHELL" = "noctalia" ]
}

@test "wayland_shell 'none' passes validation" {
  write_config '{"environment": {"desktop": "niri", "wayland_shell": "none"}}'
  _resolve_env_validate
  [ "$ENVIRONMENT_WAYLAND_SHELL" = "none" ]
}

@test "wayland_shell is honored for hyprland too" {
  write_config \
    '{"environment": {"desktop": "hyprland", "wayland_shell": "none"}}'
  _resolve_env_validate
  [ "$ENVIRONMENT_WAYLAND_SHELL" = "none" ]
}

@test "wayland_shell unknown value fails validation naming valid options" {
  write_config \
    '{"environment": {"desktop": "niri", "wayland_shell": "waybar"}}'
  run _resolve_env_validate
  [ "$status" -ne 0 ]
  [[ "$output" =~ "waybar" ]]
  [[ "$output" =~ "noctalia" ]]
}

# ── install summary environment lines ─────────────────────────────────────

@test "summary shows desktop, GPU and audio when desktop is selected" {
  ENVIRONMENT_DESKTOP=("kde")
  ENVIRONMENT_GPU=("amd")
  run print_environment_summary
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Desktop:" ]]
  [[ "$output" =~ "KDE" ]]
  [[ "$output" =~ "GPU:" ]]
  [[ "$output" =~ "AMD" ]]
  [[ "$output" =~ "Audio:" ]]
  [[ "$output" =~ "pipewire" ]]
}

@test "summary shows 'none' for audio when no desktop is selected" {
  ENVIRONMENT_DESKTOP=()
  ENVIRONMENT_GPU=("amd")
  run print_environment_summary
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Audio:" ]]
  [[ "$output" =~ "none" ]]
  [[ ! "$output" =~ "pipewire" ]]
}
