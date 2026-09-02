#!/usr/bin/env bats
# Tests for vm/lib/flow-test.sh seed rendering — the --hold-on-fail affordance
# (ADR 0099): a failed cell skips poweroff and gives ttyS0 a root autologin
# shell so it stays inspectable over serial, while the default keeps the
# self-disposing `poweroff -f` the matrix relies on.

setup() {
  info() { :; }
  warn() { :; }
  section() { :; }
  error() { echo "$*" >&2; return 1; }
  export -f info warn section error
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."

  # shellcheck source=../../vm/lib/flow-test.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/flow-test.sh"
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
}

@test "seed: default always powers off (self-disposing cell)" {
  HOLD_ON_FAIL=false
  run _flow_render_user_data https://example/repo.git
  [ "$status" -eq 0 ]
  [[ "$output" == *'===INSTALLER-EXIT-%d==='* ]]
  # Unconditional poweroff, no hold guard.
  [[ "$output" == *'poweroff -f'* ]]
  [[ "$output" != *'if [ "$rc" -eq 0 ]'* ]]
  [[ "$output" != *'serial-getty@ttyS0'* ]]
}

@test "seed: --hold-on-fail holds a failed cell with a serial autologin shell" {
  HOLD_ON_FAIL=true
  run _flow_render_user_data https://example/repo.git
  [ "$status" -eq 0 ]
  # Sentinel still emitted so the host detects the failure code.
  [[ "$output" == *'===INSTALLER-EXIT-%d==='* ]]
  # poweroff only on success; a failure sets up a root autologin getty on ttyS0.
  [[ "$output" == *'if [ "$rc" -eq 0 ]'* ]]
  [[ "$output" == *'poweroff -f'* ]]
  [[ "$output" == *'serial-getty@ttyS0'* ]]
  [[ "$output" == *'--autologin root'* ]]
}
