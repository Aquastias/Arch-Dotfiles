#!/usr/bin/env bash
# =============================================================================
# programs/system/kitty/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user (the runner grants temp NOPASSWD sudo, used here for seeding /etc/skel
# and /root), with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# Installs the FiraCode Nerd font (so kitty's font_family renders Nerd glyphs).
# The kitty config (home/) is applied by the Runner's Config Apply pass, not
# here (ADR 0134): install.sh installs the package only. This script still seeds
# the Noctalia-generated theme file (Catppuccin Mocha Sapphire default, ADR
# 0109) — seed-only/gitignored, kitty.conf includes it, so first boot and KDE
# (where Noctalia never runs the template) have color. The kitty binary is
# owned elsewhere (core packages.shell + the Noctalia preset), not here.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[kitty] error on line $LINENO" >&2' ERR

SELF="${PROGRAMS}/system/kitty"

# ── packages ───────────────────────────────────────────────────────────────
# kitty + FiraCode Nerd (extra, provides ttf-font-nerd, backs font_family). The
# program owns the kitty package: a Categorized-List package entry may not also
# name a Program (exclusivity, ADR 0115), so kitty left core packages.shell for
# here. The Noctalia preset separately ensures kitty on compositor boxes.
print_status info "Installing kitty + FiraCode Nerd font..."
${AUR_HELPER} -S --noconfirm --needed kitty ttf-firacode-nerd

# ── seed the Noctalia-generated theme (Catppuccin Mocha Sapphire default) ─────
# Seed-only/gitignored: not part of the home/ bundle. kitty.conf includes it;
# Noctalia rewrites it live only in compositor sessions, so KDE and first boot
# stay on this default.
print_status info "Seeding kitty palette theme..."
mkdir -p "${HOME}/.config/kitty/themes"
cp "${SELF}/themes/noctalia.conf" "${HOME}/.config/kitty/themes/noctalia.conf"
sudo mkdir -p /etc/skel/.config/kitty/themes
sudo cp "${SELF}/themes/noctalia.conf" \
  /etc/skel/.config/kitty/themes/noctalia.conf

# ── seed the /root theme (never receives /etc/skel; home/ comes from the pass)
# A root terminal (su -/sudo -i) gets the same palette; the kitty config subtree
# itself is placed under /root by the Config Apply pass (ADR 0134).
print_status info "Seeding kitty palette theme for root (/root)..."
sudo mkdir -p /root/.config/kitty/themes
sudo cp "${SELF}/themes/noctalia.conf" /root/.config/kitty/themes/noctalia.conf
sudo chown -R root:root /root/.config/kitty

print_status success "Kitty staged (font + palette theme)." \
  "Config applied by the Runner pass; Noctalia live-follows on compositors."
