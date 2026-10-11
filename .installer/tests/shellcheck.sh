#!/usr/bin/env bash
# =============================================================================
# tests/shellcheck.sh — Run shellcheck across .installer/
# =============================================================================
# Requires shellcheck on $PATH (sudo pacman -S shellcheck).
# Excludes .installer/tests/bats/ and itself.
# =============================================================================

set -Eeuo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
INSTALLER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "[shellcheck.sh] ERROR: shellcheck not found on PATH." >&2
  echo "  Install: sudo pacman -S --noconfirm shellcheck" >&2
  exit 127
fi
SHELLCHECK="$(command -v shellcheck)"

declare -a SHELLCHECK_ARGUMENTS
SHELLCHECK_ARGUMENTS=("$@")

declare -a TARGETS=()
while IFS= read -r -d '' command_file; do
  TARGETS+=("$command_file")
done < <(find "$INSTALLER_DIR" -type f -name '*.sh' \
  ! -path "${BASH_SOURCE[0]}" \
  ! -path "${SCRIPT_DIR}/bats/*" \
  -print0 | sort -z)
# PATH executables carry no .sh (conventions.md) — list them explicitly.
_PATH_CMDS=("$INSTALLER_DIR/aur/aur-vet")
for command_file in "${_PATH_CMDS[@]}"; do
  [[ -f "$command_file" ]] && TARGETS+=("$command_file")
done

if ((${#TARGETS[@]} == 0)); then
  echo "[shellcheck.sh] No *.sh files found under ${INSTALLER_DIR}."
  exit 0
fi

echo "[shellcheck.sh] Using ${SHELLCHECK}"
echo "[shellcheck.sh] Checking ${#TARGETS[@]} file(s) under ${INSTALLER_DIR}"
for command_file in "${TARGETS[@]}"; do
  printf '  - %s\n' "${command_file#"${INSTALLER_DIR}/"}"
done
echo ""

"$SHELLCHECK" -x -P SCRIPTDIR "${SHELLCHECK_ARGUMENTS[@]}" "${TARGETS[@]}"
echo ""
echo "[shellcheck.sh] All checked files are clean."
