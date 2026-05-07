#!/usr/bin/env bash
# =============================================================================
# lib/run-program.sh — Program Install Script runner
# =============================================================================
# Wrapper that the Runner invokes inside arch-chroot for every Program Install
# Script. Owns the contract between the Runner and a program's install.sh:
#
#   1. Verifies staging (Shell Stdlib readable, install.sh readable). On
#      failure exits 99 with a clear message — no partial execution.
#   2. Sources Shell Stdlib once, in the same shell that will source the
#      install.sh, so program scripts get its helpers without their own
#      source line.
#   3. Sources the install.sh in the same shell, inheriting `set -Eeuo
#      pipefail` from this wrapper.
#
# Expects `$OS_DIR`, `$PROGRAMS`, `$SHELL_COMMONS` already exported by the
# Runner (or by `su - <user>` for user programs). Argument: install.sh path.
# =============================================================================

set -Eeuo pipefail

SCRIPT="${1:?run-program: missing install.sh path}"

[[ -n "${SHELL_COMMONS:-}" ]] || {
  echo "[run-program] SHELL_COMMONS not set" >&2
  exit 99
}
[[ -r "${SHELL_COMMONS}/shell-stdlib.sh" ]] || {
  echo "[run-program] shell-stdlib.sh not readable: ${SHELL_COMMONS}/shell-stdlib.sh" >&2
  exit 99
}
[[ -r "${SCRIPT}" ]] || {
  echo "[run-program] install.sh not readable: ${SCRIPT}" >&2
  exit 99
}

# shellcheck source=/dev/null
source "${SHELL_COMMONS}/shell-stdlib.sh"
# shellcheck source=/dev/null
source "${SCRIPT}"
