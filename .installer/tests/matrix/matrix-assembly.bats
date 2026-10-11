#!/usr/bin/env bats
# Tier-1 assembly oracle for the Combination Matrix (combination-matrix/01,
# ADR 0046). The always-on, no-VM guarantee: every generated cell assembles to
# an Effective Config that passes the real validation_check_install_context. Prior art:
# install-print-config.bats + guided-emit.bats.
#
# The one physically-coupled check validation_check_install_context makes — the
# block-device probe (layout_disk_exists) — is stubbed here: disk existence is
# a Tier-2/VM concern with no combinatorial content, so Tier-1 exercises every
# other validator against the real INSTALLER_DIR tree. Behaviour under test: the
# cell
# the generator emits validates clean.

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export INSTALLER_DIR
  export SCRIPT_DIR="$INSTALLER_DIR"
  MATRIX_SH="$INSTALLER_DIR/tools/matrix.sh"

  # The cell → Effective Config adapter (Tier-1 input) + the generator that
  # produces the Tier-1 cells this oracle validates.
  # shellcheck source=../../lib/matrix/assemble.sh
  source "$INSTALLER_DIR/lib/matrix/assemble.sh"
  # shellcheck source=../../lib/matrix/generator.sh
  source "$INSTALLER_DIR/lib/matrix/generator.sh"
}

# _matrix_tier1_cell <id> — the generated Tier-1 cell with the given id.
_matrix_tier1_cell() {
  matrix_tier1_cells | jq -c --arg id "$1" 'select(.id == $id)'
}

# _matrix_validate_cell <cell-json> — assemble the cell to a CONFIG_FILE and run
# the real validation_check_install_context over it, mirroring 03-install.sh's module
# load + config/layout dispatch. Disk existence is stubbed (Tier-2's job).
# Echoes nothing on success; the caller asserts via `run`.
_matrix_validate_cell() {
  local cell="$1"
  local config_file; config_file="$(mktemp "${BATS_TEST_TMPDIR}/cell.XXXXXX.jsonc")"
  matrix_cell_assemble "$cell" > "$config_file"
  export CONFIG_FILE="$config_file"

  local module
  for module in lib/common.sh lib/config/categorized-list.sh \
    lib/config/post-install.sh lib/config/install-config.sh \
    lib/config/lifecycle.sh lib/config/program-registry.sh lib/config/profile-loader.sh \
    lib/layout/dispatch.sh lib/packages/package-list.sh lib/profiles/runner.sh \
    lib/config/validation.sh; do
    source "$INSTALLER_DIR/$module"
  done

  lifecycle_load_config >/dev/null 2>&1
  lifecycle_detect_mode  >/dev/null 2>&1
  local adapter
  adapter="$(root_adapter_source "$INSTALLER_DIR" \
    "$(install_config_filesystem)" "$INSTALL_MODE")"
  source "$adapter"

  # Tier-1 seam: disk existence is a VM concern, so assume present.
  layout_disk_exists() { return 0; }

  validation_check_install_context
}

# ── each single-disk plaintext root cell validates via validation_check_install_context

@test "tier-1: zfs-single-plain passes validation_check_install_context" {
  run _matrix_validate_cell "$(_matrix_tier1_cell zfs-single-plain)"
  [ "$status" -eq 0 ]
}

@test "tier-1: btrfs-single-plain passes validation_check_install_context" {
  run _matrix_validate_cell "$(_matrix_tier1_cell btrfs-single-plain)"
  [ "$status" -eq 0 ]
}

@test "tier-1: ext4-single-plain passes validation_check_install_context" {
  run _matrix_validate_cell "$(_matrix_tier1_cell ext4-single-plain)"
  [ "$status" -eq 0 ]
}

@test "tier-1: xfs-single-plain passes validation_check_install_context" {
  run _matrix_validate_cell "$(_matrix_tier1_cell xfs-single-plain)"
  [ "$status" -eq 0 ]
}

# ── the new assembler paths (impermanence, multi os_pool) validate too ──────

@test "tier-1: an impermanent zfs single cell validates" {
  run _matrix_validate_cell "$(_matrix_tier1_cell zfs-single-plain-imp)"
  [ "$status" -eq 0 ]
}

@test "tier-1: a multi-disk zfs mirror cell validates" {
  run _matrix_validate_cell "$(_matrix_tier1_cell zfs-mirror-plain)"
  [ "$status" -eq 0 ]
}
