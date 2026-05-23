#!/usr/bin/env bats
# Tests for .os/lib/shell/output.sh — print_status helper.

setup() {
  # shellcheck source=../lib/shell/output.sh
  source "$BATS_TEST_DIRNAME/../lib/shell/output.sh"
}

@test "print_status info: prefix [INFO] + message in stdout" {
  run print_status info "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" == *"hello world"* ]]
}

@test "print_status success: prefix [SUCCESS]" {
  run print_status success "done"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[SUCCESS]"* ]]
  [[ "$output" == *"done"* ]]
}

@test "print_status warning: prefix [WARNING]" {
  run print_status warning "careful"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARNING]"* ]]
  [[ "$output" == *"careful"* ]]
}

@test "print_status error: prefix [ERROR]" {
  run print_status error "boom"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ERROR]"* ]]
  [[ "$output" == *"boom"* ]]
}

@test "print_status custom <color>: message only, no level prefix" {
  run print_status custom magenta "pink text"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pink text"* ]]
  [[ "$output" != *"[SUCCESS]"* ]]
  [[ "$output" != *"[INFO]"* ]]
  [[ "$output" != *"[WARNING]"* ]]
  [[ "$output" != *"[ERROR]"* ]]
}

@test "print_status with no type: plain echo of remaining args" {
  run print_status "" "plain message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plain message"* ]]
  [[ "$output" != *"["* ]]
}
