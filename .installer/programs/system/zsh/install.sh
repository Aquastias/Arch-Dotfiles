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
# enables pkgfile-update.timer. The zsh config (home/) is applied by the
# Runner's Config Apply pass, not here (ADR 0134). install.sh still does the
# non-config work: seeds the Noctalia-generated theme files (Catppuccin Mocha
# Sapphire default, seed-only/gitignored), pre-warms the zinit plugin cache
# (from the bundle, into a throwaway env) so the first login clones nothing,
# and makes zsh root's login shell. The zsh binary + user login shell are owned
# elsewhere (User Core shell=/bin/zsh + ensure_login_shell_installed).
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

# The zsh config (home/) is applied by the Config Apply pass (ADR 0134) into
# $HOME + /etc/skel + /root — install.sh no longer copies it.

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
# Source the zinit config from the BUNDLE (+ powerlevel10k) in a throwaway
# ZDOTDIR so ~/.zinit is cloned/compiled now — install.sh no longer seeds the
# config into $HOME (the pass does), so warm from ${SELF}/home directly. The
# first interactive login then loads every plugin from disk, offline. Copy the
# warmed cache into /etc/skel so later users inherit it too.
print_status info "Pre-warming zinit plugin cache (clones plugins now)..."
_zdot="$(mktemp -d)"
cat >"${_zdot}/.zshrc" <<EOF
source "${SELF}/home/.zsh/zinit/default.zsh"
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

# ── seed /root's theme + warmed cache, and make zsh its shell ────────────────
# The zsh CONFIG under /root is placed by the Config Apply pass (ADR 0134).
# install.sh adds only the non-config bits /root needs: the STATIC default theme
# (Noctalia runs only in user sessions, so root never live-follows) and the
# warmed zinit cache. chown to root since cp -a keeps the installing user's
# ownership. The p10k `context` segment then shows a red 🔒 root@host.
print_status info "Seeding zsh theme + cache for root (/root) + root shell..."
sudo mkdir -p /root/.zsh/themes
sudo cp "${SELF}/themes/noctalia.zsh"    /root/.zsh/themes/noctalia.zsh
sudo cp "${SELF}/themes/p10k-accent.zsh" /root/.zsh/themes/p10k-accent.zsh
[[ -d "${HOME}/.zinit" ]] && sudo cp -a "${HOME}/.zinit" /root/.zinit
sudo chown -R root:root /root/.zsh /root/.zinit 2>/dev/null || true
sudo chsh -s /usr/bin/zsh root

print_status success "Zsh installed (tooling + theme + warmed zinit)." \
  "Config applied by the Runner pass; login shell from User Core."
