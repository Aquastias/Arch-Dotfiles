#!/usr/bin/env bats
# Tests for `tools/matrix.sh emit <cell-id>` (combination-matrix/01, ADR 0046).
# emit materializes one cell to an ephemeral VM Profile in tmpfs and prints its
# path. The profile carries the assembled Effective Config inline under
# `.install` (the config seam), so Tier 2 installs the exact bytes Tier 1
# assembled. Behaviour under test: the emitted profile is schema-valid to the
# VM Harness and carries the cell's config.

load ../lib/json-helpers

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export INSTALLER_DIR
  MATRIX_SH="$INSTALLER_DIR/tools/matrix.sh"

  # The VM Profile schema validator (pure jq).
  # shellcheck source=../../vm/lib/profile-validate.sh
  source "$INSTALLER_DIR/vm/lib/profile-validate.sh"
}

# ── emit writes a path to a real tmpfs profile file ─────────────────────────

@test "emit: prints a path to a materialized profile file" {
  run bash "$MATRIX_SH" emit zfs-single-plain
  [ "$status" -eq 0 ]
  [ -f "$output" ]
}

# ── the emitted profile is schema-valid to the VM Harness ───────────────────

@test "emit: the profile passes VM Profile schema validation" {
  local path; path="$(bash "$MATRIX_SH" emit zfs-single-plain)"
  local json
  # The emitted file, parsed (a parse error fails here).
  json="$(jq '.' "$path")"
  run profile_validate "$json" "$INSTALLER_DIR/hosts"
  [ "$status" -eq 0 ]
}

# ── the config seam: .install is the assembled Effective Config ─────────────

@test "emit: .install carries the assembled Effective Config for the cell" {
  local path; path="$(bash "$MATRIX_SH" emit zfs-single-plain)"
  file_satisfies "$path" '.install | type == "object"'
  file_satisfies "$path" '.install.filesystem == "zfs"'
  file_satisfies "$path" '.install.mode == "single"'
  file_satisfies "$path" '.install.disk | type == "string"'
}

# ── an unknown cell-id is rejected ──────────────────────────────────────────

@test "emit: an unknown cell-id fails, naming the id" {
  run bash "$MATRIX_SH" emit no-such-cell
  [ "$status" -ne 0 ]
  [[ "$output" == *"no-such-cell"* ]]
}
