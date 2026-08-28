#!/usr/bin/env bash
# =============================================================================
# tests/shellcheck.sh — Run shellcheck across .os/
# =============================================================================
# Requires shellcheck on $PATH (sudo pacman -S shellcheck).
# Excludes .os/tests/bats/ and itself.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "[shellcheck.sh] ERROR: shellcheck not found on PATH." >&2
  echo "  Install: sudo pacman -S --noconfirm shellcheck" >&2
  exit 127
fi
SHELLCHECK="$(command -v shellcheck)"

declare -a SHELLCHECK_ARGS
SHELLCHECK_ARGS=("$@")

declare -a TARGETS=()
while IFS= read -r -d '' f; do
  TARGETS+=("$f")
done < <(find "$OS_DIR" -type f -name '*.sh' \
  ! -path "${BASH_SOURCE[0]}" \
  ! -path "${SCRIPT_DIR}/bats/*" \
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
