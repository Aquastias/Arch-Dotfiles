#!/usr/bin/env bats
# Tests for resolve_audio_packages() in lib/config.sh.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  jsonc()   { cat "$1"; }
  cfgo()    { jsonc "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()     { jsonc "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  section() { :; }
  warn()    { :; }
  confirm() { :; }

  # shellcheck source=../lib/config.sh
  source "$BATS_TEST_DIRNAME/../lib/config.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "non-empty desktop adds PipeWire stack to packages.groups.audio" {
  ENVIRONMENT_DESKTOP=("kde")
  resolve_audio_packages
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire "* ]]
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire-pulse "* ]]
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire-alsa "* ]]
  [[ " ${AUDIO_PACKAGES[*]} " == *" wireplumber "* ]]
}

@test "two-desktop array still produces PipeWire stack (no duplicates)" {
  ENVIRONMENT_DESKTOP=("kde" "hyprland")
  resolve_audio_packages
  local count
  count=$(echo "${AUDIO_PACKAGES[*]}" | tr ' ' '\n' | grep -c "^pipewire$")
  [ "$count" -eq 1 ]
}

@test "empty desktop array produces empty audio package list" {
  ENVIRONMENT_DESKTOP=()
  resolve_audio_packages
  [ "${#AUDIO_PACKAGES[@]}" -eq 0 ]
}

@test "calling resolve_audio_packages twice does not duplicate packages" {
  ENVIRONMENT_DESKTOP=("kde")
  resolve_audio_packages
  resolve_audio_packages
  local count
  count=$(echo "${AUDIO_PACKAGES[*]}" | tr ' ' '\n' | grep -c "^pipewire$")
  [ "$count" -eq 1 ]
}
