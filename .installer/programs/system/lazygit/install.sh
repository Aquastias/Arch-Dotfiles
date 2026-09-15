#!/usr/bin/env bash
# =============================================================================
# programs/system/lazygit/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user (the runner grants temp NOPASSWD sudo, used here for seeding /etc/skel
# and /root), with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# Installs lazygit and SEEDS its config (bundled under home/, kept byte-identical
# to the repo stow tree by a drift test) into the owning user's $HOME, /etc/skel,
# and /root — the installer never stows (ADR 0095), so a fresh non-stowing user
# still gets a themed git TUI; the repo copy stays hand-stowable. The theme is
# static ANSI-16 (ADR 0132), following the terminal palette, so nothing is
# seed-only here. The program owns the lazygit package (exclusivity, ADR 0115),
# so lazygit left core packages.shell for here.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[lazygit] error on line $LINENO" >&2' ERR

SELF="${PROGRAMS}/system/lazygit"

# ── package ──────────────────────────────────────────────────────────────────
print_status info "Installing lazygit..."
${AUR_HELPER} -S --noconfirm --needed lazygit

# ── seed the config (ADR 0095: installer never stows, so seed) ───────────────
# The bundled home/ tree is byte-identical to the repo stow tree (drift test).
# Seed into the owning user's $HOME (they already exist, so /etc/skel would not
# reach them) and into /etc/skel for users created later.
print_status info "Seeding lazygit config into \$HOME and /etc/skel..."
cp -a "${SELF}/home/." "${HOME}/"
sudo cp -a "${SELF}/home/." /etc/skel/

# ── seed /root (never receives /etc/skel) ────────────────────────────────────
# A root lazygit gets the same themed config; cp -a keeps the installing user's
# ownership, so chown the seeded subtree back to root.
print_status info "Seeding lazygit config for root (/root)..."
sudo cp -a "${SELF}/home/." /root/
sudo chown -R root:root /root/.config/lazygit

print_status success "Lazygit staged (seeded ANSI-16 config)." \
  "Repo copy stays hand-stowable; follows the terminal palette."
