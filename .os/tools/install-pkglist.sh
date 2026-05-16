#!/usr/bin/env bash
# Installs packages for the current (or specified) host from
# .os/hosts/<hostname>/pkglist-repo.txt and pkglist-aur.txt.
#
# Usage: install-pkglist.sh [hostname]
#   hostname defaults to $(hostname)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(dirname "$SCRIPT_DIR")"

hostname="${1:-$(hostname)}"
host_dir="${OS_DIR}/hosts/${hostname}"

if [[ ! -d "$host_dir" ]]; then
  echo "No host dir at ${host_dir}" >&2
  exit 1
fi

repo_list="${host_dir}/pkglist-repo.txt"
aur_list="${host_dir}/pkglist-aur.txt"

if [[ ! -f "$repo_list" ]]; then
  echo "No repo list at ${repo_list}" >&2
  exit 1
fi

if ! command -v paru &>/dev/null; then
  echo "paru not found — install it first" >&2
  exit 1
fi

echo "Installing repo packages for ${hostname}..."
paru -S --needed - < "$repo_list"

if [[ -f "$aur_list" ]]; then
  echo "Installing AUR packages for ${hostname}..."
  paru -S --needed - < "$aur_list"
fi

echo "Done."
