#!/usr/bin/env bash
# =============================================================================
# programs/dev/nvim/install.sh
# =============================================================================
# Sourced by .installer/lib/profiles/runner.sh inside arch-chroot as the owning
# user, with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# The Neovim config (home/) is applied by the Runner's Config Apply pass, not
# here (ADR 0134). The LSP/formatter toolchain is declared in Host Core
# language-servers as bare packages (editor-agnostic, no mason — ADR 0135), so
# the base install already places it. This program only stages the config and
# installs the ONE best-effort exception: Swift's sourcekit-lsp, which ships
# with the AUR swift-bin toolchain (AUR-only, heavy). It is attempted but never
# fails the install — a missing Swift is an optional gap, not a broken editor
# (ADR 0135/0136). It also installs the plugins pinned by lazy-lock.json, so
# the editor works offline from first launch.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[nvim] error on line $LINENO" >&2' ERR

SELF="${PROGRAMS}/dev/nvim"

# PHP LSP (ADR 0135): phpactor's AUR build check() and its runtime need php's
# iconv extension, which Arch ships (iconv.so) but leaves DISABLED — so phpactor
# can't be a bare package (its build aborts: "iconv extension is not installed",
# VM-verified). Enable iconv, then install phpactor here in the user-program
# phase. php is installed here too: a host with `packages.inherit: false`
# (e.g. the arch-kde VM fixture) never gets Host Core's dev php.
print_status info "Enabling php iconv + installing phpactor (PHP LSP)..."
${AUR_HELPER} -S --noconfirm --needed php
echo 'extension=iconv' | sudo tee /etc/php/conf.d/iconv.ini >/dev/null
${AUR_HELPER} -S --noconfirm --needed phpactor
# phpcbf (PHP formatter) needs php too, so it rides the same step.
${AUR_HELPER} -S --noconfirm --needed php-codesniffer

# lazy.nvim installs rest.nvim's rock deps with system luarocks against Lua 5.1
# (hererocks is off: Python bootstrap). Installed here, not Host Core, so
# `packages.inherit: false` hosts get them too (ADR 0150).
print_status info "Installing luarocks + lua51 (rest.nvim rocks) + jq..."
${AUR_HELPER} -S --noconfirm --needed luarocks lua51 jq

print_status info "Installing Swift toolchain (sourcekit-lsp) — best-effort..."
if ${AUR_HELPER} -S --noconfirm --needed swift-bin; then
  print_status success "Swift toolchain installed (sourcekit-lsp available)."
else
  print_status warning "Swift unavailable; sourcekit-lsp skipped (optional)."
fi

# ── seed the Noctalia-generated theme (Catppuccin Mocha Sapphire default) ─────
# Seed-only/gitignored (ADR 0136): nvim loads it only when follow_noctalia is
# on. Noctalia rewrites it live on compositors, so KDE and first boot keep this
# default. Three targets like kitty: the user, /etc/skel, and /root.
print_status info "Seeding Neovim palette theme..."
mkdir -p "${HOME}/.config/nvim/themes"
cp "${SELF}/themes/noctalia.lua" "${HOME}/.config/nvim/themes/noctalia.lua"
sudo mkdir -p /etc/skel/.config/nvim/themes
sudo cp "${SELF}/themes/noctalia.lua" \
  /etc/skel/.config/nvim/themes/noctalia.lua
sudo mkdir -p /root/.config/nvim/themes
sudo cp "${SELF}/themes/noctalia.lua" /root/.config/nvim/themes/noctalia.lua
sudo chown -R root:root /root/.config/nvim

# ── plugins at install, pinned by the committed lazy-lock.json ──────────────
# lazy.nvim would fetch every plugin on first launch, so an offline first boot
# had no plugins (Feature Audit runtime fetch). Restore now, for the user and
# root (both get this config), from the staged config: Config Apply copies
# home/ only after this script. Builds (parsers, rocks) run here too.
# orgmode builds its own tree-sitter grammar on first use (a clone + compile):
# do it here too, waiting on its promise.
_org="lua local p = require('orgmode.utils.treesitter.install').install()"
_org+=" if p then p:wait(300000) end"
_restore=(--headless "+Lazy! restore" "+Lazy! load orgmode" "+$_org" +qa)
# lazy rewrites lazy-lock.json on restore; the staged tree is read-only, so
# restore from a throwaway copy.
_cfg="$(mktemp -d)"
cp -r "${SELF}/home/.config/nvim" "$_cfg/"
print_status info "Installing Neovim plugins (lazy-lock.json)..."
XDG_CONFIG_HOME="$_cfg" nvim "${_restore[@]}" \
  || print_status warning "Neovim plugin restore failed for" \
  "${USER}; lazy.nvim installs them on first launch (needs network)."
sudo -H env XDG_CONFIG_HOME="$_cfg" nvim "${_restore[@]}" \
  || print_status warning "Neovim plugin restore failed for root."
sudo rm -rf "$_cfg"

print_status success "Neovim staged." \
  "Config applied by the Runner pass; LSP toolchain from Host Core."
