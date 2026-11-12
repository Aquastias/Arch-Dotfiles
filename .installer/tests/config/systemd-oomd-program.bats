#!/usr/bin/env bats
# system/systemd-oomd program — the drop-ins that make oomd act. Arch's systemd
# ships the daemon but no ManagedOOM* defaults, so it would monitor nothing;
# the program mirrors Fedora's systemd-oomd-defaults. Runs install.sh against a
# temp root (OOMD_ROOT seam).

load ../lib/json-helpers

setup() {
  INSTALL="$BATS_TEST_DIRNAME/../../programs/system/systemd-oomd/install.sh"
  CONFIG="$BATS_TEST_DIRNAME/../../programs/system/systemd-oomd/config.jsonc"
  export OOMD_ROOT="$BATS_TEST_TMPDIR/root"
}

_run_install() {
  run bash -c 'print_status() { :; }; source "$0"' "$INSTALL"
}

@test "system slices are killed under sustained memory pressure" {
  _run_install
  [ "$status" -eq 0 ]
  local dropin="$OOMD_ROOT/etc/systemd/system/system.slice.d"
  dropin+="/10-oomd-per-slice-defaults.conf"
  grep -qx '\[Slice\]' "$dropin"
  grep -qx 'ManagedOOMMemoryPressure=kill' "$dropin"
  grep -qx 'ManagedOOMMemoryPressureLimit=80%' "$dropin"
}

@test "every user-manager slice gets the same pressure policy" {
  _run_install
  local dropin="$OOMD_ROOT/etc/systemd/user/slice.d"
  dropin+="/10-oomd-per-slice-defaults.conf"
  grep -qx 'ManagedOOMMemoryPressure=kill' "$dropin"
  grep -qx 'ManagedOOMMemoryPressureLimit=80%' "$dropin"
}

@test "oomd acts after 20s of pressure, Fedora's duration" {
  _run_install
  local dropin="$OOMD_ROOT/etc/systemd/oomd.conf.d/10-oomd-defaults.conf"
  grep -qx '\[OOM\]' "$dropin"
  grep -qx 'DefaultMemoryPressureDurationSec=20s' "$dropin"
}

@test "the runner enables systemd-oomd.service" {
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  json_satisfies "$(jsonc_strip "$CONFIG")" '.kind == "host"
    and .system_services == ["systemd-oomd.service"]'
}
