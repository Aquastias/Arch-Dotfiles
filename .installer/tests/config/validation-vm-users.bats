#!/usr/bin/env bats
# Install-time validation finds a VM fixture user the way the Profile Loader
# does: users/<name>, else users/vm/<name> (profile_loader_directory). The
# headless/secure VM profile names `test` (users/vm/test); validation used to
# check users/<name> only and aborted that install. No VM: the profile's
# Effective Config is assembled host-side and run through the installer's own
# validation (block-device probe stubbed).

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export INSTALLER_DIR
  # shellcheck source=../../lib/jsonc.sh
  source "$INSTALLER_DIR/lib/jsonc.sh"
  # shellcheck source=../../lib/feature-audit/manifest.sh
  source "$INSTALLER_DIR/lib/feature-audit/manifest.sh"
}

@test "a host naming a VM fixture user (users/vm/<name>) validates" {
  local config
  config="$(bash "$INSTALLER_DIR/vm/vm.sh" --testing \
    --profile headless/secure --print-config 2>/dev/null)"
  jq -e '.users == ["test"]' <<<"$config"
  run feature_audit_validate_config "$config"
  [ "$status" -eq 0 ]
}
