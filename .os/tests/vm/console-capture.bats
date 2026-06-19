#!/usr/bin/env bats
# Tests for the boot-verify console capture in .os/vm/lib/flow-test.sh. A serial
# PTY can drop mid-boot (notably the slower multi-disk boot), so the capture
# re-attaches `virsh console` until the domain halts rather than attaching once —
# otherwise the first-boot marker printed after the drop is lost and boot-verify
# wrongly fails. This drives _console_capture_loop with stubbed script/_vm_running.

setup() {
  TEST_DIR="$(mktemp -d)"
  info() { :; }
  warn() { :; }
  section() { :; }
  error() { echo "$*" >&2; return 1; }
  export -f info warn section error
  export OS_DIR="$BATS_TEST_DIRNAME/../.."

  # shellcheck source=../../vm/lib/flow-test.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/flow-test.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "_console_capture_loop: re-attaches across drops until the domain halts" {
  local log="$TEST_DIR/cap.log" cnt="$TEST_DIR/cnt"
  : > "$log"; echo 0 > "$cnt"
  VM_NAME="dummy"

  # Each stub `script` is one console attach that ends (a dropped PTY); the loop
  # must re-attach while the domain runs.
  script() { printf 'attach\n' >> "$log"; }
  # running for the first two checks, halted on the third.
  _vm_running() {
    local n; n="$(cat "$cnt")"; echo $((n + 1)) > "$cnt"
    [ "$n" -lt 2 ]
  }

  _console_capture_loop "$log"
  [ "$(grep -c attach "$log")" -eq 3 ]   # 3 attaches, then break on halt
}

@test "_console_capture_loop: a single attach that outlives the domain stops" {
  local log="$TEST_DIR/cap.log"
  : > "$log"
  VM_NAME="dummy"

  script() { printf 'attach\n' >> "$log"; }
  _vm_running() { return 1; }            # already halted after the first attach

  _console_capture_loop "$log"
  [ "$(grep -c attach "$log")" -eq 1 ]
}
