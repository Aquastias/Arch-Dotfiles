#!/usr/bin/env bash
# =============================================================================
# programs/dev/vscodium/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot as the owning
# user with temp NOPASSWD sudo, with INSTALLER_DIR, PROGRAMS, SHELL_COMMONS and
# AUR_HELPER pre-exported.
#
# Installs vscodium-bin (AUR), then every extension in extensions.txt from Open
# VSX for this user (ADR 0148). Additive only: never uninstalls, so a user's
# own extensions survive a re-run. A failed extension warns instead of failing
# the install — an Open VSX blip is a gap, not a broken editor. The config
# (home/) is applied by the Runner's Config Apply pass (ADR 0134), not here.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[vscodium] error on line $LINENO" >&2' ERR

SELF="${PROGRAMS}/dev/vscodium"

print_status info "Installing VSCodium (vscodium-bin)..."
${AUR_HELPER} -S --noconfirm --needed vscodium-bin

print_status info "Installing VSCodium extensions from Open VSX..."
failed=()
while IFS= read -r id; do
  [[ "$id" =~ ^[[:space:]]*(#|$) ]] && continue
  codium --install-extension "$id" >/dev/null 2>&1 || failed+=("$id")
done <"${SELF}/extensions.txt"

if ((${#failed[@]})); then
  print_status warning "Extensions not installed: ${failed[*]}"
fi

print_status success "VSCodium staged." \
  "Config applied by the Runner pass; toolchain from Host Core."
