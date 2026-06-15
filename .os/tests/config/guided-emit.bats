#!/usr/bin/env bats
# Tests for .os/lib/config/emit.sh — the Guided Installer's Emitter (ADR 0039):
# a Config State (+ optional disk assignment) → a device-baked Effective Config
# merged over Host Core. Pure: JSON-in/JSON-out, no TTY, no disk writes.
#
# Behaviour under test (external only — the effective config the emitter
# produces), never internal structure.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  mkdir -p "$OS_DIR/hosts/core"
  printf '%s\n' \
    '{"system_programs":["cups"],"sysctl":{"vm.swappiness":10}}' \
    > "$OS_DIR/hosts/core/profile.jsonc"

  # shellcheck source=../../lib/config/state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  # shellcheck source=../../lib/config/emit.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
  # validate_config_schema — assert the guided output is schema-clean.
  # shellcheck source=../../lib/config/profile.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── tracer: single-disk ZFS Effective Config over Host Core ─────────────────

@test "emit_effective: bakes hostname + picked disk merged over Host Core" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" mode '"single"')"
  assignment='{"mode":"single","disk":"/dev/disk/by-id/wwn-0xDEAD"}'

  run emit_effective "$state" "$assignment"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'
  echo "$output" | jq -e '.mode == "single"'
  echo "$output" | jq -e '.disk == "/dev/disk/by-id/wwn-0xDEAD"'
  # Host Core still applies under the guided session.
  echo "$output" | jq -e '.system_programs == ["cups"]'
  echo "$output" | jq -e '.sysctl["vm.swappiness"] == 10'
}

# ── safety: the guided output is as schema-clean as a hand-authored profile ─

@test "emit_effective: the produced config passes closed-schema validation" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" mode '"single"')"
  assignment='{"mode":"single","disk":"/dev/disk/by-id/wwn-0xDEAD"}'

  effective="$(emit_effective "$state" "$assignment")"
  run validate_config_schema host "$effective"
  [ "$status" -eq 0 ]
}
