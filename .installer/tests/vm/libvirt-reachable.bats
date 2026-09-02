#!/usr/bin/env bats
# Tests for _ensure_libvirt_reachable in vm/lib/core.sh — the sandbox-fallback
# signal (ADR 0099). When virsh cannot reach libvirtd, the message must tell an
# agent whether this is a sandbox-blocked socket (retry outside the sandbox) or a
# genuinely down daemon. Stubs virsh + systemctl so no real libvirt is needed.

setup() {
  # shellcheck source=../../vm/lib/core.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/core.sh"
  # Override common.sh's error (which exits) so `run` can capture the message.
  error() { echo "$*"; return 1; }
}

@test "reachable: virsh connects → returns 0, no signal" {
  virsh() { echo "qemu:///system"; return 0; }
  run _ensure_libvirt_reachable
  [ "$status" -eq 0 ]
}

@test "unreachable but daemon up → 'sandbox?' signal to retry outside sandbox" {
  virsh() { echo "error: failed to connect to the hypervisor" >&2; return 1; }
  systemctl() { [[ "$1 $2" == "is-active --quiet" ]] && return 0; }
  run _ensure_libvirt_reachable
  [ "$status" -ne 0 ]
  [[ "$output" == *'libvirt unreachable (sandbox?)'* ]]
  [[ "$output" == *'sandbox disabled'* ]]
  [[ "$output" == *'vm-sandbox.md'* ]]
}

@test "unreachable and daemon down → plain 'libvirt unreachable' signal" {
  virsh() { echo "error: failed to connect to the hypervisor" >&2; return 1; }
  systemctl() { return 1; }   # libvirtd not active
  run _ensure_libvirt_reachable
  [ "$status" -ne 0 ]
  [[ "$output" == *'libvirt unreachable'* ]]
  [[ "$output" != *'(sandbox?)'* ]]
}
