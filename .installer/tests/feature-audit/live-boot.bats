#!/usr/bin/env bats
# Boot fatals keep host-side evidence (Audit Run 20261003): base and
# niri-pure never reached SSH with an empty serial log, and `virsh start`'s
# own errors were discarded, so nothing said why.

setup() {
  T="$(mktemp -d)"
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  VM_NAME=arch-audit
  # shellcheck source=../../lib/common.sh
  source "$INSTALLER_DIR/lib/common.sh"
  # shellcheck source=../../lib/feature-audit/live.sh
  source "$INSTALLER_DIR/lib/feature-audit/live.sh"
  virsh() {
    case "$1" in
      start) echo "error: failed to start domain" >&2; return 1 ;;
      domstate) echo "running (booted)" ;;
      screenshot) echo img > "$3" ;;
    esac
  }
  _vm_capacity_preflight() { :; }
}

teardown() { rm -rf "$T"; }

@test "fa_vm_start keeps virsh start's error in the phase dir" {
  fa_vm_start "$T/boot1"
  grep -q 'failed to start domain' "$T/boot1/virsh-start.err"
}

@test "fa_boot_evidence saves domain state and a console screenshot" {
  fa_boot_evidence "$T/boot1"
  grep -q 'running (booted)' "$T/boot1/domstate.txt"
  [ -s "$T/boot1/console.png" ]
}
