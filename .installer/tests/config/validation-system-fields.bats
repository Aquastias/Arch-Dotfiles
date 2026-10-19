#!/usr/bin/env bats
# Tests for _validation_system_fields (lib/config/validation.sh): the hostname
# check and the Host Profile it resolves for secrets + the Profiles Runner.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"
  export INSTALLER_DIR="$TEST_DIR/installer"
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  info() { :; }; warn() { :; }; section() { :; }
  # shellcheck source=../../lib/config/profile-loader.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile-loader.sh"
  # shellcheck source=../../lib/config/validation.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/validation.sh"
  mkdir -p "$INSTALLER_DIR/hosts/core" "$INSTALLER_DIR/hosts/desktop"
  echo '{}' >"$INSTALLER_DIR/hosts/core/profile.jsonc"
  echo '{"system":{"hostname":"eterniox"}}' \
    >"$INSTALLER_DIR/hosts/desktop/profile.jsonc"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "validation resolves the Host Profile behind the hostname (ADR 0020)" {
  # RESOLVED_HOST_PROFILE was the hostname, so desktop's secrets, users and
  # program contracts were looked up under hosts/eterniox and silently missed.
  echo '{"system":{"hostname":"eterniox","locale":["en_US.UTF-8"]}}' \
    >"$CONFIG_FILE"
  _validation_system_fields
  [ "$RESOLVED_HOSTNAME" = "eterniox" ]
  [ "$RESOLVED_HOST_PROFILE" = "desktop" ]
}
