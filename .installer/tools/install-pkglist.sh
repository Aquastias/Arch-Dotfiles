#!/usr/bin/env bash
# Installs packages from a drift snapshot written by save-pkglist.sh:
# .os/hosts/<profile>/pkglist-repo.txt and pkglist-aur.txt.
#
# Usage: install-pkglist.sh [profile]
#   profile defaults to $SAVE_PKGLIST_PROFILE, else $(hostname)
#
# Takes a PROFILE name, not a hostname (ADR 0020) — same resolution as
# save-pkglist.sh, so the two agree on where the files live. The snapshots
# carry a `#` header; it is stripped here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../lib/aur-helper.sh
source "${OS_DIR}/lib/aur-helper.sh"

profile="${1:-${SAVE_PKGLIST_PROFILE:-$(hostname)}}"
host_dir="${OS_DIR}/hosts/${profile}"
[[ -d "$host_dir" ]] || host_dir="${OS_DIR}/hosts/vm/${profile}"

if [[ ! -d "$host_dir" ]]; then
  {
    echo "install-pkglist: no profile '${profile}' under ${OS_DIR}/hosts/"
    echo "This takes a PROFILE name (a hosts/<name>/ directory), not a"
    echo "hostname — ADR 0020 decoupled the two."
  } >&2
  exit 1
fi

repo_list="${host_dir}/pkglist-repo.txt"
aur_list="${host_dir}/pkglist-aur.txt"

if [[ ! -f "$repo_list" ]]; then
  echo "No repo list at ${repo_list} — run save-pkglist.sh first" >&2
  exit 1
fi

# Resolve the AUR Helper (ADR 0052) via the shared rule: paru preferred, yay the
# fallback. Runs on a booted system, so it reads the real PATH.
if ! helper="$(_profiles_detect_helper)"; then
  echo "no AUR helper found (paru or yay) — install one first" >&2
  exit 1
fi

# Drop the drift-snapshot header and any blank lines. Pure bash — this runs
# under a minimal PATH in the tests, so it must not need grep.
_pkgs() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    printf '%s\n' "$line"
  done < "$1"
}

echo "Installing repo packages for profile ${profile}..."
_pkgs "$repo_list" | "$helper" -S --needed -

if [[ -f "$aur_list" ]] && [[ -n "$(_pkgs "$aur_list")" ]]; then
  echo "Installing AUR packages for profile ${profile}..."
  _pkgs "$aur_list" | "$helper" -S --needed -
fi

echo "Done."
