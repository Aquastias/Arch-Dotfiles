#!/usr/bin/env bats
# Tests for resolve_environment() in lib/config/environment.sh — the single public
# seam. Drives the module end-to-end with a fixture install.jsonc and asserts
# the five resolved globals populate. Stubs lspci so GPU "auto" is hermetic.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  jsonc_strip() { cat "$1"; }
  cfgo()    { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()     { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
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

@test "resolve_environment populates all five globals from config" {
  write_config '{"environment": {"desktop": "kde", "gpu": "nvidia"}}'
  resolve_environment
  [ "${ENVIRONMENT_DESKTOP[0]}" = "kde" ]
  [ "${ENVIRONMENT_GPU[0]}" = "nvidia" ]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  [ "${#GPU_PARU_PACKAGES[@]}" -eq 0 ]
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire "* ]]
}

@test "resolve_environment is idempotent: second call produces identical state" {
  write_config '{"environment": {"desktop": "kde", "gpu": "nvidia"}}'
  resolve_environment
  local d1="${ENVIRONMENT_DESKTOP[*]}"
  local g1="${ENVIRONMENT_GPU[*]}"
  local gp1="${GPU_PACMAN_PACKAGES[*]}"
  local gr1="${GPU_PARU_PACKAGES[*]}"
  local a1="${AUDIO_PACKAGES[*]}"
  resolve_environment
  [ "${ENVIRONMENT_DESKTOP[*]}" = "$d1" ]
  [ "${ENVIRONMENT_GPU[*]}" = "$g1" ]
  [ "${GPU_PACMAN_PACKAGES[*]}" = "$gp1" ]
  [ "${GPU_PARU_PACKAGES[*]}" = "$gr1" ]
  [ "${AUDIO_PACKAGES[*]}" = "$a1" ]
}

@test "resolve_environment with gpu='auto' mutates ENVIRONMENT_GPU to detected vendors" {
  write_config '{"environment": {"desktop": null, "gpu": "auto"}}'
  _gpu_lspci_output() {
    echo "00:02.0 VGA compatible controller [0300]: NVIDIA Corp [10de:1234]"
  }
  resolve_environment
  [ "${ENVIRONMENT_GPU[0]}" = "nvidia" ]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
  resolve_environment
  [ "${ENVIRONMENT_GPU[0]}" = "nvidia" ]
  [[ " ${GPU_PACMAN_PACKAGES[*]} " == *" nvidia-open-dkms "* ]]
}
