#!/usr/bin/env bash
# =============================================================================
# tests/shellcheck.sh — Run shellcheck across .os/
# =============================================================================
# Resolves shellcheck in this order:
#   1. .os/tests/shellcheck-bin/shellcheck (vendored static binary)
#   2. shellcheck on $PATH (pacman -S shellcheck)
# Excludes .os/tests/bats/ and .os/tests/shellcheck-bin/ and itself.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -x "${SCRIPT_DIR}/shellcheck-bin/shellcheck" ]]; then
  SHELLCHECK="${SCRIPT_DIR}/shellcheck-bin/shellcheck"
elif command -v shellcheck >/dev/null 2>&1; then
  SHELLCHECK="$(command -v shellcheck)"
else
  echo "[shellcheck.sh] ERROR: shellcheck not found." >&2
  echo "  Install:  sudo pacman -S --noconfirm shellcheck" >&2
  echo "  Or vendor: download static binary into .os/tests/shellcheck-bin/" >&2
  exit 127
fi

declare -a SHELLCHECK_ARGS
SHELLCHECK_ARGS=("$@")

declare -a TARGETS=()
while IFS= read -r -d '' f; do
  TARGETS+=("$f")
done < <(find "$OS_DIR" -type f -name '*.sh' \
  ! -path "${BASH_SOURCE[0]}" \
  ! -path "${SCRIPT_DIR}/bats/*" \
  ! -path "${SCRIPT_DIR}/shellcheck-bin/*" \
  -print0 | sort -z)

if ((${#TARGETS[@]} == 0)); then
  echo "[shellcheck.sh] No *.sh files found under ${OS_DIR}."
  exit 0
fi

echo "[shellcheck.sh] Using ${SHELLCHECK}"
echo "[shellcheck.sh] Checking ${#TARGETS[@]} file(s) under ${OS_DIR}"
for f in "${TARGETS[@]}"; do
  printf '  - %s\n' "${f#"${OS_DIR}/"}"
done
echo ""

"$SHELLCHECK" -x -P SCRIPTDIR "${SHELLCHECK_ARGS[@]}" "${TARGETS[@]}"
echo ""
echo "[shellcheck.sh] All checked files are clean."
