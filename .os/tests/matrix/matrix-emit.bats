#!/usr/bin/env bats
# Tests for `tools/matrix.sh emit <cell-id>` (combination-matrix/01, ADR 0046).
# emit materializes one cell to an ephemeral VM Profile in tmpfs and prints its
# path. The profile carries the assembled Effective Config inline under
# `.install` (the config seam), so Tier 2 installs the exact bytes Tier 1
# assembled. Behaviour under test: the emitted profile is schema-valid to the
# VM Harness and carries the cell's config.

setup() {
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export OS_DIR
  MATRIX_SH="$OS_DIR/tools/matrix.sh"

  # The VM Profile schema validator (pure jq).
  # shellcheck source=../../vm/lib/profile-validate.sh
  source "$OS_DIR/vm/lib/profile-validate.sh"
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
  local json; json="$(jq '.' "$path")"
  run profile_validate "$json" "$OS_DIR/hosts"
  [ "$status" -eq 0 ]
}

# ── the config seam: .install is the assembled Effective Config ─────────────

@test "emit: .install carries the assembled Effective Config for the cell" {
  local path; path="$(bash "$MATRIX_SH" emit zfs-single-plain)"
  jq -e '.install | type == "object"'        "$path"
  jq -e '.install.filesystem == "zfs"'        "$path"
  jq -e '.install.mode == "single"'           "$path"
  jq -e '.install.disk | type == "string"'    "$path"
}

# ── an unknown cell-id is rejected ──────────────────────────────────────────

@test "emit: an unknown cell-id fails, naming the id" {
  run bash "$MATRIX_SH" emit no-such-cell
  [ "$status" -ne 0 ]
  [[ "$output" == *"no-such-cell"* ]]
}
