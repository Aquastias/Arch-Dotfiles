#!/usr/bin/env bash
# =============================================================================
# programs/system/zsh/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user (the runner grants temp NOPASSWD sudo, used here for: `pkgfile -u` to
# build the root-owned pkgfile database and seeding /etc/skel), with
# INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# Installs the interactive zsh tooling — eza, zoxide, fzf, nvm, pv, age,
# python-pygments (colorize), pkgfile (command-not-found), ttf-meslo-nerd (p10k
# glyphs), all repo; git-extras from the AUR. Builds the pkgfile database and
# enables pkgfile-update.timer. SEEDS the full zsh config
# (bundled under home/, kept byte-identical to the repo root by a drift test)
# into the owning user's $HOME and into /etc/skel — the installer never stows
# (ADR 0095), so a fresh non-stowing user still gets a working shell; the
# repo-root copy stays hand-stowable. Seeds the Noctalia-generated theme files
# (Catppuccin Mocha Sapphire default). Pre-warms the zinit plugin cache so the
# first interactive login clones nothing. The zsh binary and login shell are
# owned elsewhere (User Core shell=/bin/zsh + ensure_login_shell_installed).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[zsh] error on line $LINENO" >&2' ERR

SELF="${PROGRAMS}/system/zsh"

# ── packages ─────────────────────────────────────────────────────────────────
print_status info "Installing zsh tooling..."
${AUR_HELPER} -S --noconfirm --needed \
  eza zoxide fzf pv age python-pygments pkgfile ttf-meslo-nerd nvm \
  bat tree pnpm git-extras

# ── pkgfile database (command-not-found) ─────────────────────────────────────
# pkgfile keeps its own file index; build it now (chroot has network). The
# OMZ command-not-found plugin sources /usr/share/doc/pkgfile/command-not-found.zsh
# at login; pkgfile-update.timer keeps it fresh (enabled via config.jsonc).
print_status info "Building pkgfile database..."
sudo pkgfile -u
# The runner enables system_services only for host programs, so this user
# program enables pkgfile's shipped timer itself (enable, never start — ADR
# 0026 / PROGRAM_SPEC). Keeps the index fresh after first boot.
sudo systemctl enable pkgfile-update.timer

# ── seed the full zsh config (ADR 0095: installer never stows, so seed) ───────
# The bundled home/ tree is byte-identical to the repo-root config (drift test).
# Seed into the owning user's $HOME (they already exist, so /etc/skel would not
# reach them) and into /etc/skel for users created later.
print_status info "Seeding zsh config into \$HOME and /etc/skel..."
cp -a "${SELF}/home/." "${HOME}/"
sudo cp -a "${SELF}/home/." /etc/skel/

# ── seed the Noctalia-generated theme (Catppuccin Mocha Sapphire default) ─────
# Seed-only/gitignored: not part of the home/ bundle. Ships a default so first
# boot and KDE (where Noctalia never runs the template) have color.
print_status info "Seeding zsh palette theme..."
mkdir -p "${HOME}/.zsh/themes"
cp "${SELF}/themes/noctalia.zsh"    "${HOME}/.zsh/themes/noctalia.zsh"
cp "${SELF}/themes/p10k-accent.zsh" "${HOME}/.zsh/themes/p10k-accent.zsh"
sudo mkdir -p /etc/skel/.zsh/themes
sudo cp "${SELF}/themes/noctalia.zsh"    /etc/skel/.zsh/themes/noctalia.zsh
sudo cp "${SELF}/themes/p10k-accent.zsh" /etc/skel/.zsh/themes/p10k-accent.zsh

# ── pre-warm the zinit plugin cache ──────────────────────────────────────────
# Source the just-seeded zinit config (+ powerlevel10k) in a throwaway ZDOTDIR
# so ~/.zinit is cloned/compiled now; the first interactive login then loads
# every plugin from disk, offline — the arch-combined "clean stderr" bar. Copy
# the warmed cache into /etc/skel so later users inherit it too.
print_status info "Pre-warming zinit plugin cache (clones plugins now)..."
_zdot="$(mktemp -d)"
cat >"${_zdot}/.zshrc" <<EOF
source "${HOME}/.zsh/zinit/default.zsh"
zinit light romkatv/powerlevel10k
EOF
ZDOTDIR="${_zdot}" zsh -i -c 'exit' >/dev/null 2>&1 || true
rm -rf "${_zdot}"

if [[ -f "${HOME}/.zinit/bin/zinit.zsh" ]]; then
  print_status info "zinit cache warmed; seeding it into /etc/skel."
  sudo cp -a "${HOME}/.zinit" /etc/skel/.zinit
else
  print_status warning "zinit pre-warm did not populate ~/.zinit;" \
    "first login will clone plugins."
fi

print_status success "Zsh staged (tooling + seeded config + warmed zinit)." \
  "Login shell comes from User Core; repo copy stays hand-stowable."
