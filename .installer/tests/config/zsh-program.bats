#!/usr/bin/env bats
# system/zsh program + zsh Theme Template (ADR 0128 pattern). Static seam like
# pi-agent.bats / noctalia-stow.bats: assert the COMMITTED program definition,
# payload, config fixes, and Noctalia wiring without running an install.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."       # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/system/zsh"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOMESEED="$PROG/home"
  SEED_FZF="$PROG/themes/noctalia.zsh"
  SEED_P10K="$PROG/themes/p10k-accent.zsh"
  ZSHRC="$REPO/.zshrc"
  P10KSRC="$REPO/.zsh/vendors/p10k/default.zsh"
  ZSTYLE="$REPO/.zsh/zstyle/default.zsh"
  ALIASES="$REPO/.zsh_aliases"
  UCORE="$REPO/.installer/users/core/profile.jsonc"
  GI="$REPO/.gitignore"
  CT="$REPO/.config/noctalia/config.toml"
  TPL_FZF="$REPO/.config/noctalia/templates/zsh.zsh"
  TPL_P10K="$REPO/.config/noctalia/templates/p10k-accent.zsh"
}

# ── program definition ───────────────────────────────────────────────────────

@test "system/zsh config.jsonc declares the user-kind zsh program" {
  [ -f "$CFG" ]
  grep -q '"name": "zsh"' "$CFG"
  grep -q '"kind": "user"' "$CFG"
}

@test "install.sh has the mandated shape and installs the tooling" {
  [ -f "$INSTALL" ]
  # set -Eeuo pipefail + trap are the first two non-comment lines (PROGRAM_SPEC)
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$INSTALL' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  # packages via the AUR helper; nvm is repo (extra), git-extras is the only AUR
  grep -q '${AUR_HELPER} -S --noconfirm --needed' "$INSTALL"
  for p in eza zoxide fzf pv age python-pygments pkgfile ttf-meslo-nerd nvm \
           git-extras; do
    grep -q "$p" "$INSTALL"
  done
  grep -q 'sudo pkgfile -u' "$INSTALL"
  # user programs don't get system_services enabled by the runner, so the
  # timer is enabled in-script (enable, never start)
  grep -q 'systemctl enable pkgfile-update.timer' "$INSTALL"
  grep -q 'print_status success' "$INSTALL"
  ! grep -qE 'systemctl (start|restart)' "$INSTALL"
}

@test "install.sh seeds the full config into \$HOME and /etc/skel (ADR 0095)" {
  grep -q 'cp -a "${SELF}/home/." "${HOME}/"' "$INSTALL"
  grep -q 'sudo cp -a "${SELF}/home/." /etc/skel/' "$INSTALL"
  # pre-warms zinit against the seeded config
  grep -q 'source "${HOME}/.zsh/zinit/default.zsh"' "$INSTALL"
}

@test "bundled home/ config is byte-identical to the repo root (drift)" {
  [ -d "$HOMESEED" ]
  # every seeded file matches its committed repo-root source, no drift
  # (themes/ is generated/seed-only, excluded from the bundle)
  diff -r -x themes "$REPO/.zsh" "$HOMESEED/.zsh"
  for f in .zshrc .zshenv .zsh_aliases .p10k.zsh; do
    diff -q "$REPO/$f" "$HOMESEED/$f"
  done
  # the generated theme dir is NOT bundled (seeded separately, gitignored)
  [ ! -e "$HOMESEED/.zsh/themes" ]
}

# ── seed theme: Catppuccin Mocha Sapphire default ────────────────────────────

@test "seeded noctalia.zsh sets fzf + syntax to the Sapphire palette" {
  [ -f "$SEED_FZF" ]
  grep -q 'FZF_DEFAULT_OPTS' "$SEED_FZF"
  grep -q 'prompt:#74c7ec' "$SEED_FZF"                 # accent = sapphire
  grep -q "ZSH_HIGHLIGHT_STYLES\[command\]='fg=#74c7ec'" "$SEED_FZF"
  grep -q "ZSH_HIGHLIGHT_STYLES\[unknown-token\]='fg=#f38ba8,bold'" "$SEED_FZF"
}

@test "seeded p10k-accent.zsh overrides only accent foregrounds" {
  [ -f "$SEED_P10K" ]
  grep -q "POWERLEVEL9K_DIR_FOREGROUND='#74c7ec'" "$SEED_P10K"
  grep -q "POWERLEVEL9K_OS_ICON_FOREGROUND='#74c7ec'" "$SEED_P10K"
  # only *_FOREGROUND keys — no backgrounds or unrelated prompt config
  ! grep -qE 'POWERLEVEL9K_[A-Z_]*BACKGROUND' "$SEED_P10K"
}

@test "generated theme is seed-only: gitignored, never in the stow tree" {
  grep -q '^\.zsh/themes/' "$GI"
  [ ! -e "$REPO/.zsh/themes/noctalia.zsh" ]
  [ ! -e "$REPO/.zsh/themes/p10k-accent.zsh" ]
}

# ── Noctalia live-follow wiring ──────────────────────────────────────────────

@test "config.toml registers both zsh user-templates → seed-only outputs" {
  grep -q '\[theme.templates.user.zsh\]' "$CT"
  grep -qE 'output_path[[:space:]]*=.*\.zsh/themes/noctalia\.zsh' "$CT"
  grep -q '\[theme.templates.user.p10k-accent\]' "$CT"
  grep -qE 'output_path[[:space:]]*=.*\.zsh/themes/p10k-accent\.zsh' "$CT"
}

@test "template inputs use Mustache Material-role placeholders" {
  [ -f "$TPL_FZF" ]
  grep -q 'prompt:{{colors.primary.default.hex}}' "$TPL_FZF"
  grep -q "ZSH_HIGHLIGHT_STYLES\[command\]='fg={{colors.primary.default.hex}}'" \
    "$TPL_FZF"
  [ -f "$TPL_P10K" ]
  grep -q "POWERLEVEL9K_DIR_FOREGROUND='{{colors.primary.default.hex}}'" \
    "$TPL_P10K"
}

# ── .zshrc / config fixes ────────────────────────────────────────────────────

@test ".zshrc fixes the p10k instant-prompt ordering and sources the theme" {
  # POWERLEVEL9K_INSTANT_PROMPT is set BEFORE the instant-prompt cache source
  run bash -c "grep -n 'POWERLEVEL9K_INSTANT_PROMPT=quiet' '$ZSHRC' | cut -d: -f1"
  ip_line="$output"
  run bash -c "grep -n 'p10k-instant-prompt' '$ZSHRC' | head -1 | cut -d: -f1"
  [ "$ip_line" -lt "$output" ]
  # the generated theme is sourced
  grep -q '\.zsh/themes/noctalia.zsh' "$ZSHRC"
  # no redundant re-source of ~/.zshenv (zsh auto-sources it)
  ! grep -qE 'source[[:space:]]+"?\$HOME/\.zshenv' "$ZSHRC"
}

@test "p10k loader sources the accent override after .p10k.zsh" {
  run bash -c "grep -n '\.p10k.zsh' '$P10KSRC' | tail -1 | cut -d: -f1"
  p10k_line="$output"
  run bash -c "grep -n 'p10k-accent.zsh' '$P10KSRC' | tail -1 | cut -d: -f1"
  [ "$output" -gt "$p10k_line" ]
}

@test "nvm is lazy OMZ-only with NVM_DIR set — no eager init-nvm.sh source" {
  grep -q "zstyle ':omz:plugins:nvm' lazy yes" "$ZSTYLE"
  # NVM_DIR points the OMZ plugin at Arch's /usr/share/nvm (else nvm is absent)
  grep -q 'export NVM_DIR="/usr/share/nvm"' "$REPO/.zsh/env/exports.zsh"
  ! grep -rq '/usr/share/nvm/init-nvm.sh' "$REPO/.zsh" "$ZSHRC"
  [ ! -e "$REPO/.zsh/vendors/nodejs" ]
}

@test "dead config files are removed" {
  [ ! -e "$REPO/.zsh/welcome" ]
  [ ! -e "$REPO/.zsh/env/evals.zsh" ]
}

@test "alias pruning: web + ckb-reload cut, anime + freshclam kept" {
  ! grep -q "alias web=" "$ALIASES"
  ! grep -q "ckb-reload" "$ALIASES"
  grep -q "alias anime=" "$ALIASES"
  grep -q "freshclam" "$ALIASES"
}

# ── profile wiring ───────────────────────────────────────────────────────────

@test "Noctalia template inputs are staged + seeded (live-follow, seed-only)" {
  # config.toml declares the templates; their input files must reach /etc/skel
  # on a non-stowing box or Noctalia can't render them (live-follow no-ops).
  local chroot="$REPO/.installer/lib/chroot.sh"
  local preset="$REPO/.installer/lib/chroot/noctalia-preset.sh"
  # staged into the curated dir for both wlroots adapters (niri + hyprland)
  [ "$(grep -c 'noctalia/templates' "$chroot")" -ge 2 ]
  # seeded curated -> /etc/skel by the preset
  grep -q 'noctalia/templates' "$preset"
}

@test "User Core serves the zsh program fleet-wide" {
  grep -qE '"programs":.*"zsh"' "$UCORE"
}
