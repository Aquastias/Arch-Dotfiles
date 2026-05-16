#!/usr/bin/env bash
# Saves installed packages for the current (or specified) host to
# .os/hosts/<hostname>/pkglist-repo.txt and pkglist-aur.txt.
#
# Usage: save-pkglist.sh [hostname]
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

pacman -Qqen > "${host_dir}/pkglist-repo.txt"
pacman -Qqem > "${host_dir}/pkglist-aur.txt"
echo "Saved to ${host_dir}/"
