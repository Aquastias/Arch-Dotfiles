#!/usr/bin/env bash
# =============================================================================
# programs/system/kitty/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user (the runner grants temp NOPASSWD sudo, used here for seeding /etc/skel
# and /root), with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# Installs the FiraCode Nerd font (so kitty's font_family renders Nerd glyphs)
# and SEEDS the full kitty config (bundled under home/, kept byte-identical to
# the repo stow tree by a drift test) into the owning user's $HOME, /etc/skel,
# and /root — the installer never stows (ADR 0095), so a fresh non-stowing user
# still gets a themed terminal; the repo copy stays hand-stowable. Seeds the
# Noctalia-generated theme file (Catppuccin Mocha Sapphire default, ADR 0109) —
# seed-only/gitignored, kitty.conf includes it, so first boot and KDE (where
# Noctalia never runs the template) have color. The kitty binary is owned
# elsewhere (core packages.shell + the Noctalia preset), not installed here.
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

# ── seed the full kitty config (ADR 0095: installer never stows, so seed) ─────
# The bundled home/ tree is byte-identical to the repo-root config (drift test).
# Seed into the owning user's $HOME (they already exist, so /etc/skel would not
# reach them) and into /etc/skel for users created later.
print_status info "Seeding kitty config into \$HOME and /etc/skel..."
cp -a "${SELF}/home/." "${HOME}/"
sudo cp -a "${SELF}/home/." /etc/skel/

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

# ── seed /root (never receives /etc/skel) ─────────────────────────────────────
# A root terminal (su -/sudo -i) gets the same themed config; cp -a keeps the
# installing user's ownership, so chown the seeded kitty subtree back to root.
print_status info "Seeding kitty config for root (/root)..."
sudo cp -a "${SELF}/home/." /root/
sudo mkdir -p /root/.config/kitty/themes
sudo cp "${SELF}/themes/noctalia.conf" /root/.config/kitty/themes/noctalia.conf
sudo chown -R root:root /root/.config/kitty

print_status success "Kitty staged (font + seeded config + palette theme)." \
  "Repo copy stays hand-stowable; Noctalia live-follows on compositors."
