#!/usr/bin/env bash
# Downloads the newest archzfs-Compatible Arch ISO (the one the installer
# can build ZFS against) and verifies its sha256, ready to flash to a USB
# stick. Download-only — it does not flash anything.
#
# Run on your current machine (Arch) before booting the installer:
#   bash .installer/tools/fetch-iso.sh [output-dir]
#     output-dir defaults to ~/Downloads
#
# See CONTEXT.md (archzfs-Compatible ISO) and ADR 0023 for why the latest
# Arch ISO cannot be used.

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
INSTALLER_DIR="${SCRIPT_DIR%/*}"
# shellcheck source=../lib/common.sh
source "${INSTALLER_DIR}/lib/common.sh"
# shellcheck source=../lib/packages/iso-resolver.sh
source "${INSTALLER_DIR}/lib/packages/iso-resolver.sh"

# Resolve + create the output directory: positional arg, else ~/Downloads.
fetch_iso_output_directory() {
  local directory="${1:-${HOME}/Downloads}"
  mkdir -p "$directory" || return 1
  printf '%s\n' "$directory"
}

# Print the resolved ISO path and a flashing hint.
fetch_iso_print_result() {
  local iso="$1"
  info "Compatible ISO ready:"
  printf '  %s\n\n' "$iso"
  echo "Flash it to a USB stick, e.g.:"
  printf '  sudo dd if=%s of=/dev/sdX bs=4M status=progress oflag=sync\n' \
    "$iso"
  echo "  (or use Ventoy / Impression / Rufus)"
}

# Resolve + download the compatible ISO into output_directory, verify its
# sha256, then print the path and flash hint.
fetch_iso_run() {
  local output_directory="$1" iso
  iso="$(iso_resolver_get_zfs_compatible "$output_directory")" || return 1
  if ! iso_resolver_verify_sha256 "$iso"; then
    echo "fetch-iso: checksum verification failed; removing ${iso}" >&2
    rm -f "$iso"
    return 1
  fi
  fetch_iso_print_result "$iso"
}

# Install jq/curl via pacman if missing (assumes an Arch prep machine).
# Only this step needs root; the download itself runs unprivileged.
fetch_iso_ensure_deps() {
  local missing=()
  command_exists jq   || missing+=(jq)
  command_exists curl || missing+=(curl)
  ((${#missing[@]})) || return 0
  info "Installing missing dependencies: ${missing[*]}"
  sudo pacman -Sy --noconfirm "${missing[@]}"
}

main() {
  fetch_iso_ensure_deps
  local output_directory
  output_directory="$(fetch_iso_output_directory "${1:-}")"
  fetch_iso_run "$output_directory"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi
