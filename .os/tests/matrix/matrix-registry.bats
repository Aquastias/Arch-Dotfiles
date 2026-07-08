#!/usr/bin/env bats
# Tests for the Axis Registry (combination-matrix/02, ADR 0046) — the
# stay-in-sync enforcer. It maps every _MENU_FIELDS path to a role
# (storage-cluster / scalar-sweep / pairwise-affecting / inert) and a
# light/heavy weight, and asserts it covers _MENU_FIELDS EXACTLY: a menu field
# with no entry, or an entry for a non-existent field, hard-fails. Behaviour
# under test is the assertion + the lookups, never how the table is stored.

setup() {
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export OS_DIR
  # _MENU_FIELDS lives in menu.sh; the registry classifies it.
  # shellcheck source=../../lib/config/menu.sh
  source "$OS_DIR/lib/config/menu.sh"
  # shellcheck source=../../lib/matrix/registry.sh
  source "$OS_DIR/lib/matrix/registry.sh"
  # the generator invokes the assertion before emitting.
  # shellcheck source=../../lib/matrix/cells.sh
  source "$OS_DIR/lib/matrix/cells.sh"
}

# ── tracer: the shipped registry covers _MENU_FIELDS exactly ────────────────

@test "registry_assert: the shipped registry covers _MENU_FIELDS exactly" {
  run matrix_registry_assert
  [ "$status" -eq 0 ]
}

# ── a new menu field with no registry entry hard-fails, naming the path ──────

@test "registry_assert: an unclassified menu field fails, naming it" {
  _MENU_FIELDS+=("Disks|options.newthing|new thing|")
  run matrix_registry_assert
  [ "$status" -ne 0 ]
  [[ "$output" == *"unclassified axis options.newthing"* ]]
}

# ── a registry entry for a field the menu no longer offers hard-fails ────────

@test "registry_assert: a stale registry entry fails, naming it" {
  _MATRIX_AXIS_REGISTRY+=("options.ghost|inert|light")
  run matrix_registry_assert
  [ "$status" -ne 0 ]
  [[ "$output" == *"stale registry entry options.ghost"* ]]
}

# ── role / weight lookups return the registered values ──────────────────────

@test "role/weight lookups return the registered values" {
  [ "$(matrix_axis_role filesystem)" = "storage-cluster" ]
  [ "$(matrix_axis_role environment.desktop)" = "pairwise-affecting" ]
  [ "$(matrix_axis_weight environment.desktop)" = "heavy" ]
  [ "$(matrix_axis_role system.hostname)" = "inert" ]
  [ "$(matrix_axis_weight options.esp_size)" = "light" ]
  run matrix_axis_role no.such.path
  [ "$status" -ne 0 ]
}

# ── the generator refuses to emit while the registry has a gap ──────────────

@test "gen: aborts (no cells) when the registry doesn't cover _MENU_FIELDS" {
  _MENU_FIELDS+=("Disks|options.newthing|new thing|")
  run matrix_gen_cells
  [ "$status" -ne 0 ]
  [[ "$output" == *"unclassified axis options.newthing"* ]]
}
