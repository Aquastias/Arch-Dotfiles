#!/usr/bin/env bash
# =============================================================================
# stow-configs.sh — apply per-program config from each program's home/ (ADR 0134)
# =============================================================================
# The operator's day-2 twin of the Runner's install-time config-apply pass.
# Each Program owns its user config under
# `.installer/programs/<cat>/<name>/home/` (a subtree mirroring $HOME); this
# stows the selected ones into $HOME with GNU stow. Single source — the folder
# layout IS the manifest; there is no repo-root stow tree.
#
#   ./stow-configs.sh                 # stow every Program that ships a home/
#   ./stow-configs.sh kitty zsh       # stow exactly these
#   ./stow-configs.sh --except claude # stow everything but claude's config
#
# `--adopt` makes it safe whether $HOME is empty (fresh clone) or already
# installer-seeded (same bytes, single source): it flips real files to symlinks
# without changing content.
# =============================================================================

set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRAMS="${REPO}/.installer/programs"
# shellcheck source=.installer/lib/config/config-apply.sh
source "${REPO}/.installer/lib/config/config-apply.sh"

usage() {
  sed -n '4,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

command -v stow >/dev/null 2>&1 \
  || { echo "stow-configs.sh: GNU stow is not installed" >&2; exit 1; }
[[ -d "$PROGRAMS" ]] \
  || { echo "stow-configs.sh: no programs dir at ${PROGRAMS}" >&2; exit 1; }

# Args: positional names (the `only` set) OR `--except <names…>`.
declare -a except=() only=()
mode="only"
while (($#)); do
  case "$1" in
  --except) mode="except" ;;
  -h | --help) usage 0 ;;
  -*) echo "stow-configs.sh: unknown flag '$1'" >&2; usage 1 ;;
  *) if [[ "$mode" == "except" ]]; then except+=("$1"); else only+=("$1"); fi ;;
  esac
  shift
done

# Bash array → compact JSON array ([] when empty).
_json_arr() {
  (($#)) || { printf '[]'; return 0; }
  printf '%s\n' "$@" | jq -R . | jq -s -c .
}

ships="$(ca_ships_home_list "$PROGRAMS")"
selection="$(ca_stow_selection "$ships" \
  "$(_json_arr "${except[@]+"${except[@]}"}")" \
  "$(_json_arr "${only[@]+"${only[@]}"}")")"

count=0
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  home="$(ca_home_dir "$PROGRAMS" "$name")" || {
    echo "stow-configs.sh: '${name}' ships no home/ — skipping" >&2; continue; }
  stow -d "$(dirname "$home")" -t "$HOME" --adopt --no-folding home
  echo "stow-configs.sh: stowed ${name}"
  count=$((count + 1))
done < <(jq -r '.[]' <<<"$selection")

echo "stow-configs.sh: ${count} program(s) stowed into ${HOME}"
