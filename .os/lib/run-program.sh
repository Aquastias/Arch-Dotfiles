#!/usr/bin/env bash
# =============================================================================
# lib/run-program.sh — Program Install Script runner
# =============================================================================
# Wrapper that the Runner invokes inside arch-chroot for every Program Install
# Script. Owns the contract between the Runner and a program's install.sh:
#
#   1. Verifies $SCRIPT is readable (per-program, not a staging invariant).
#      Exits 99 on failure — no partial execution.
#   2. Sources Shell Stdlib once, in the same shell that will source the
#      install.sh, so program scripts get its helpers without their own
#      source line.
#   3. Sources the install.sh in the same shell, inheriting `set -Eeuo
#      pipefail` from this wrapper.
#
# Staging integrity (shell-stdlib.sh readable, run-program.sh present) is
# guaranteed by validate_staging before arch-chroot is entered.
# Expects `$OS_DIR`, `$PROGRAMS`, `$SHELL_COMMONS` exported by the Runner.
# Argument: install.sh path.
# =============================================================================

set -Eeuo pipefail

SCRIPT="${1:?run-program: missing install.sh path}"

[[ -r "${SCRIPT}" ]] || {
  echo "[run-program] install.sh not readable: ${SCRIPT}" >&2
  exit 99
}

# shellcheck source=/dev/null
source "${SHELL_COMMONS}/shell-stdlib.sh"
# shellcheck source=/dev/null
source "${SCRIPT}"
