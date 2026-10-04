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

@test "fa_await_new_boot: a reboot wedged in shutdown is reset, recorded" {
  # Audit Run 20261004: virgl stalls left GPU clients in D state, so the
  # guest never finished shutting down and the variant went fatal.
  FA_SHUTDOWN_GRACE_SEC=10
  fa_agent() { echo old-id; }           # still the old boot
  sleep() { :; }
  virsh() { echo "virsh $*" >> "$T/virsh.log"; }
  fa_await_new_boot "$T/boot2" old-id
  grep -q 'virsh reset arch-audit' "$T/virsh.log"
  grep -q 'shutdown' "$T/boot2/vm-reset.txt"
}

@test "fa_await_new_boot: a clean reboot is left alone" {
  FA_SHUTDOWN_GRACE_SEC=10
  fa_agent() { echo new-id; }
  sleep() { :; }
  virsh() { echo "virsh $*" >> "$T/virsh.log"; }
  fa_await_new_boot "$T/boot2" old-id
  [ ! -e "$T/virsh.log" ]
  [ ! -e "$T/boot2/vm-reset.txt" ]
}

@test "fa_phase_wanted: an undeclared phase is skipped and recorded" {
  FA_VARIANT_PHASES="boot2 upgrade"
  ! fa_phase_wanted "$T/v" keybinds
  grep -qx 'SKIP phase-keybinds not in this variant'"'"'s Variant Phases' \
    "$T/v/keybinds/phase@gate.probe"
  fa_phase_wanted "$T/v" boot2
  [ ! -e "$T/v/boot2" ]
}

@test "fa_phase_wanted: FEATURE_AUDIT_SKIP drops a phase silently" {
  FA_VARIANT_PHASES="boot2 upgrade" FEATURE_AUDIT_SKIP="boot2"
  ! fa_phase_wanted "$T/v" boot2
  [ ! -e "$T/v/boot2" ]
}
