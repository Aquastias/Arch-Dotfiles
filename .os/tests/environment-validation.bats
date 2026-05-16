#!/usr/bin/env bats
# Tests for validate_environment() in lib/config.sh.
#
# Strategy: stub common.sh helpers (cfgo, jsonc, error, info, section, warn)
# so the module can be sourced without a live system. Happy-path tests call
# validate_environment() directly and assert globals. Error-path tests use
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

  # shellcheck source=../lib/environment.sh
  source "$BATS_TEST_DIRNAME/../lib/environment.sh"
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
  validate_environment
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 1 ]
  [ "${ENVIRONMENT_DESKTOP[0]}" = "kde" ]
}

@test "desktop 'hyprland' passes validation" {
  write_config '{"environment": {"desktop": "hyprland", "gpu": "auto"}}'
  validate_environment
  [ "${ENVIRONMENT_DESKTOP[0]}" = "hyprland" ]
}

@test "desktop array ['kde','hyprland'] passes and sets two-element array" {
  write_config \
    '{"environment": {"desktop": ["kde", "hyprland"], "gpu": "auto"}}'
  validate_environment
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 2 ]
  [ "${ENVIRONMENT_DESKTOP[0]}" = "kde" ]
  [ "${ENVIRONMENT_DESKTOP[1]}" = "hyprland" ]
}

@test "desktop null passes validation and gives empty array" {
  write_config '{"environment": {"desktop": null, "gpu": "auto"}}'
  validate_environment
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 0 ]
}

@test "environment key missing entirely passes validation" {
  write_config '{"mode": "single", "disk": "/dev/sda"}'
  validate_environment
  [ "${#ENVIRONMENT_DESKTOP[@]}" -eq 0 ]
}

@test "desktop 'gnome' fails validation with error naming valid options" {
  write_config '{"environment": {"desktop": "gnome", "gpu": "auto"}}'
  run validate_environment
  [ "$status" -ne 0 ]
  [[ "$output" =~ "kde" ]]
  [[ "$output" =~ "hyprland" ]]
}

@test "gpu 'auto' passes validation" {
  write_config '{"environment": {"desktop": null, "gpu": "auto"}}'
  validate_environment
  [ "${ENVIRONMENT_GPU[0]}" = "auto" ]
}

@test "gpu 'amd', 'nvidia', 'intel' each pass validation" {
  for vendor in amd nvidia intel; do
    write_config \
      "{\"environment\": {\"desktop\": null, \"gpu\": \"${vendor}\"}}"
    validate_environment
    [ "${ENVIRONMENT_GPU[0]}" = "$vendor" ]
  done
}

@test "gpu array ['amd','nvidia'] passes and sets two-element array" {
  write_config '{"environment": {"desktop": null, "gpu": ["amd", "nvidia"]}}'
  validate_environment
  [ "${#ENVIRONMENT_GPU[@]}" -eq 2 ]
  [ "${ENVIRONMENT_GPU[0]}" = "amd" ]
  [ "${ENVIRONMENT_GPU[1]}" = "nvidia" ]
}

@test "gpu 'vulkan' fails validation with error naming valid options" {
  write_config '{"environment": {"desktop": null, "gpu": "vulkan"}}'
  run validate_environment
  [ "$status" -ne 0 ]
  [[ "$output" =~ "amd" ]]
  [[ "$output" =~ "nvidia" ]]
}

# ── install summary environment lines ─────────────────────────────────────

@test "summary shows desktop, GPU and audio when desktop is selected" {
  ENVIRONMENT_DESKTOP=("kde")
  ENVIRONMENT_GPU=("amd")
  run print_environment_summary
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Desktop:" ]]
  [[ "$output" =~ "kde" ]]
  [[ "$output" =~ "GPU:" ]]
  [[ "$output" =~ "amd" ]]
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
