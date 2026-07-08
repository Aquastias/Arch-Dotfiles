#!/usr/bin/env bats
# Tier-1 assembly oracle for the Combination Matrix (combination-matrix/01,
# ADR 0046). The always-on, no-VM guarantee: every generated cell assembles to
# an Effective Config that passes the real validate_install_context. Prior art:
# install-print-config.bats + guided-emit.bats.
#
# The one physically-coupled check validate_install_context makes — the
# block-device probe (_layout_disk_exists) — is stubbed here: disk existence is
# a Tier-2/VM concern with no combinatorial content, so Tier-1 exercises every
# other validator against the real OS_DIR tree. Behaviour under test: the cell
# the generator emits validates clean.

setup() {
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export OS_DIR
  export SCRIPT_DIR="$OS_DIR"
  MATRIX_SH="$OS_DIR/tools/matrix.sh"

  # The cell → Effective Config adapter (Tier-1 input).
  # shellcheck source=../../lib/matrix/assemble.sh
  source "$OS_DIR/lib/matrix/assemble.sh"
}

# _matrix_validate_cell <cell-json> — assemble the cell to a CONFIG_FILE and run
# the real validate_install_context over it, mirroring 03-install.sh's module
# load + config/layout dispatch. Disk existence is stubbed (Tier-2's job).
# Echoes nothing on success; the caller asserts via `run`.
_matrix_validate_cell() {
  local cell="$1"
  local cfg; cfg="$(mktemp "${BATS_TEST_TMPDIR}/cell.XXXXXX.jsonc")"
  matrix_cell_assemble "$cell" > "$cfg"
  export CONFIG_FILE="$cfg"

  local m
  for m in lib/common.sh lib/config/categorized-list.sh \
    lib/config/post-install.sh lib/config/accessors.sh \
    lib/config/lifecycle.sh lib/config/layers.sh lib/config/profile.sh \
    lib/layout/dispatch.sh lib/packages/list.sh lib/profiles/runner.sh \
    lib/config/validation.sh; do
    source "$OS_DIR/$m"
  done

  load_config >/dev/null 2>&1
  detect_mode  >/dev/null 2>&1
  local adapter
  adapter="$(root_adapter_source "$OS_DIR" \
    "$(install_config_filesystem)" "$INSTALL_MODE")"
  source "$adapter"

  # Tier-1 seam: disk existence is a VM concern, so assume present.
  _layout_disk_exists() { return 0; }

  validate_install_context
}

# ── tracer: the generated cell validates clean via validate_install_context ──

@test "tier-1: the generated tracer cell passes validate_install_context" {
  local cell; cell="$(bash "$MATRIX_SH" gen)"
  run _matrix_validate_cell "$cell"
  [ "$status" -eq 0 ]
}
