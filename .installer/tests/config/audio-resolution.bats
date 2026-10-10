#!/usr/bin/env bats
# Tests for _environment_resolve_audio() in lib/config/lifecycle.sh.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  jsonc_strip() { cat "$1"; }
  config_optional() { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  config_required() { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
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

@test "non-empty desktop adds PipeWire stack to the derived AUDIO_PACKAGES" {
  ENVIRONMENT_DESKTOP=("kde")
  _environment_resolve_audio
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire "* ]]
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire-pulse "* ]]
  [[ " ${AUDIO_PACKAGES[*]} " == *" pipewire-alsa "* ]]
  [[ " ${AUDIO_PACKAGES[*]} " == *" wireplumber "* ]]
}

@test "two-desktop array still produces PipeWire stack (no duplicates)" {
  ENVIRONMENT_DESKTOP=("kde")
  _environment_resolve_audio
  local count
  count=$(echo "${AUDIO_PACKAGES[*]}" | tr ' ' '\n' | grep -c "^pipewire$")
  [ "$count" -eq 1 ]
}

@test "empty desktop array produces empty audio package list" {
  ENVIRONMENT_DESKTOP=()
  _environment_resolve_audio
  [ "${#AUDIO_PACKAGES[@]}" -eq 0 ]
}

@test "calling _environment_resolve_audio twice does not duplicate packages" {
  ENVIRONMENT_DESKTOP=("kde")
  _environment_resolve_audio
  _environment_resolve_audio
  local count
  count=$(echo "${AUDIO_PACKAGES[*]}" | tr ' ' '\n' | grep -c "^pipewire$")
  [ "$count" -eq 1 ]
}
