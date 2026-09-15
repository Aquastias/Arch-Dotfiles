#!/usr/bin/env bash
# =============================================================================
# programs/system/yazi/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user (the runner grants temp NOPASSWD sudo, used here for seeding /etc/skel
# and /root), with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# Installs yazi and SEEDS its theme (bundled under home/, kept byte-identical to
# the repo stow tree by a drift test) into the owning user's $HOME, /etc/skel,
# and /root — the installer never stows (ADR 0095), so a fresh non-stowing user
# still gets a themed file manager; the repo copy stays hand-stowable. The theme
# is static ANSI-16 (ADR 0132), following the terminal palette, so nothing is
# seed-only here. The program owns the yazi package (exclusivity, ADR 0115), so
# yazi left core packages.shell for here.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[yazi] error on line $LINENO" >&2' ERR

SELF="${PROGRAMS}/system/yazi"

# ── package ──────────────────────────────────────────────────────────────────
print_status info "Installing yazi..."
${AUR_HELPER} -S --noconfirm --needed yazi

# ── seed the theme (ADR 0095: installer never stows, so seed) ────────────────
# The bundled home/ tree is byte-identical to the repo stow tree (drift test).
# Seed into the owning user's $HOME (they already exist, so /etc/skel would not
# reach them) and into /etc/skel for users created later.
print_status info "Seeding yazi theme into \$HOME and /etc/skel..."
cp -a "${SELF}/home/." "${HOME}/"
sudo cp -a "${SELF}/home/." /etc/skel/

# ── seed /root (never receives /etc/skel) ────────────────────────────────────
# A root yazi gets the same themed config; cp -a keeps the installing user's
# ownership, so chown the seeded subtree back to root.
print_status info "Seeding yazi theme for root (/root)..."
sudo cp -a "${SELF}/home/." /root/
sudo chown -R root:root /root/.config/yazi

print_status success "Yazi staged (seeded ANSI-16 theme)." \
  "Repo copy stays hand-stowable; follows the terminal palette."
