#!/usr/bin/env bash
# Downloads the newest archzfs-Compatible Arch ISO (the one the installer
# can build ZFS against) and verifies its sha256, ready to flash to a USB
# stick. Download-only — it does not flash anything.
#
# Run on your current machine (Arch) before booting the installer:
#   bash .os/tools/fetch-iso.sh [output-dir]
#     output-dir defaults to ~/Downloads
#
# See CONTEXT.md (archzfs-Compatible ISO) and ADR 0023 for why the latest
# Arch ISO cannot be used.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/common.sh
source "${OS_DIR}/lib/common.sh"
# shellcheck source=../lib/packages/iso-resolver.sh
source "${OS_DIR}/lib/packages/iso-resolver.sh"

# Resolve + create the output directory: positional arg, else ~/Downloads.
fetch_iso_out_dir() {
  local dir="${1:-${HOME}/Downloads}"
  mkdir -p "$dir" || return 1
  printf '%s\n' "$dir"
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

# Resolve + download the compatible ISO into out_dir, verify its sha256,
# then print the path and flash hint.
fetch_iso_run() {
  local out_dir="$1" iso
  iso="$(iso_resolver_get_zfs_compatible "$out_dir")" || return 1
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
  local need=()
  command -v jq   >/dev/null 2>&1 || need+=(jq)
  command -v curl >/dev/null 2>&1 || need+=(curl)
  ((${#need[@]})) || return 0
  info "Installing missing dependencies: ${need[*]}"
  sudo pacman -Sy --noconfirm "${need[@]}"
}

main() {
  fetch_iso_ensure_deps
  local out_dir
  out_dir="$(fetch_iso_out_dir "${1:-}")"
  fetch_iso_run "$out_dir"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi
