#!/usr/bin/env bats
# Pi coding agent (ADR 0127/0128). Static seam mirroring noctalia-stow.bats:
# assert the COMMITTED payload + program definition + package/profile wiring,
# without running an install. Ticket 01 scope: install + base config seeded +
# stow-ready + auth gitignored + packages/profile wired.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."      # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/pi"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  ASEED="$PROG/agent"                     # bundled seed payload (under .installer)
  ASTOW="$REPO/.pi/agent"                 # repo-root hand-stow copy
  SEED="$ASEED/settings.json"
  STOW="$ASTOW/settings.json"
  CORE="$REPO/.installer/hosts/core/profile.jsonc"
  UCORE="$REPO/.installer/users/core/profile.jsonc"
  GI="$REPO/.gitignore"
  SKILLS="$REPO/.agents/skills"       # vendored mattpocock skills (stow tree)
  CT="$REPO/.config/noctalia/config.toml"
  TPL="$REPO/.config/noctalia/templates/pi.json"   # Noctalia user-template input
}

# ── program definition ───────────────────────────────────────────────────────

@test "dev/pi config.jsonc declares the user-kind pi program" {
  [ -f "$CFG" ]
  grep -q '"name": "pi"' "$CFG"
  grep -q '"kind": "user"' "$CFG"
}

@test "dev/pi install.sh installs pi-coding-agent-bin via the AUR helper" {
  [ -x "$INSTALL" ]
  grep -q '${AUR_HELPER} -S --noconfirm --needed pi-coding-agent-bin' "$INSTALL"
  # seeds the whole bundled agent payload; never writes the secret auth.json
  grep -q 'cp -r "${PROGRAMS}/dev/pi/agent/\." "${HOME}/.pi/agent/"' "$INSTALL"
  run grep -qE '(cp|tee|>)[^#]*auth\.json' "$INSTALL"
  [ "$status" -ne 0 ]
}

# ── base config: seeded payload ──────────────────────────────────────────────

@test "seeded settings.json pins provider/model/thinking/trust (ADR 0127)" {
  [ -f "$SEED" ]
  grep -q '"defaultProvider": "anthropic"' "$SEED"
  grep -q '"defaultModel": "claude-opus-4-8"' "$SEED"
  grep -q '"defaultThinkingLevel": "high"' "$SEED"
  grep -q '"defaultProjectTrust": "ask"' "$SEED"
  grep -q '"quietStartup": true' "$SEED"
  grep -q '"enabledModels"' "$SEED"
}

@test "repo-root .pi stow copy exists and matches the seed (no drift)" {
  [ -f "$STOW" ]
  # the hand-stow copy and the installer seed must be byte-identical
  diff -q "$SEED" "$STOW"
}

# ── secret handling ──────────────────────────────────────────────────────────

@test "auth.json is gitignored and absent from the stow tree (ADR 0127)" {
  grep -q '^\.pi/agent/auth.json' "$GI"
  [ ! -e "$REPO/.pi/agent/auth.json" ]
}

# ── package + profile wiring ─────────────────────────────────────────────────

@test "pi's tool deps resolve: ripgrep + fd in core, git in the base list" {
  # git ships in the Base Package List (base.sh) — not re-declared in core, or
  # packages.bats flags it as a base-list duplicate.
  grep -q '"ripgrep"' "$CORE"
  grep -q '"fd"' "$CORE"
  grep -qE '\bgit\b' "$REPO/.installer/lib/packages/base.sh"
  ! grep -q '"git"' "$CORE"
}

@test "User Core serves pi fleet-wide (ADR 0127)" {
  grep -qE '"programs":.*"pi"' "$UCORE"
}

# ── ticket 02: vendored mattpocock skills ────────────────────────────────────

@test "the full mattpocock skill set is vendored under .agents/skills" {
  [ -d "$SKILLS" ]
  # "all of them" — a generous floor so a partial vendor is caught
  [ "$(find "$SKILLS" -name SKILL.md | wc -l)" -ge 30 ]
  for s in tdd research code-review diagnosing-bugs domain-modeling wizard; do
    [ -f "$SKILLS/$s/SKILL.md" ]
  done
}

@test "vendored skills are real copies, not symlinks (offline, committed)" {
  run find "$SKILLS" -maxdepth 1 -type l
  [ -z "$output" ]
}

@test "pi auto-discovers ~/.agents/skills — settings declares no skills key" {
  ! grep -q '"skills"' "$SEED"
  ! grep -q '"skills"' "$STOW"
}

# ── ticket 03: web / todo / MCP packages ─────────────────────────────────────

@test "settings declares the web, todo and MCP packages (ADR 0127)" {
  grep -q '"npm:pi-web-access"' "$SEED"
  grep -q '"npm:@juicesharp/rpiv-todo"' "$SEED"
  grep -q '"npm:pi-mcp-adapter"' "$SEED"
}

@test "web-search.json routes SearXNG-first with a DuckDuckGo fallback" {
  for f in "$ASEED/web-search.json" "$ASTOW/web-search.json"; do
    [ -f "$f" ]
    grep -q '"searxngBaseUrl": "http://127.0.0.1:8080"' "$f"
    grep -q '"searxng"' "$f"
    grep -q '"duckduckgo"' "$f"
  done
  diff -q "$ASEED/web-search.json" "$ASTOW/web-search.json"
}

@test "starter mcp.json is a valid mcpServers shape with no committed secret" {
  for f in "$ASEED/mcp.json" "$ASTOW/mcp.json"; do
    [ -f "$f" ]
    grep -q '"mcpServers"' "$f"
    # no raw API keys baked in — secrets, if any, use ${VAR} interpolation
    run grep -qiE '(api[_-]?key|token|secret)"[[:space:]]*:[[:space:]]*"[^$]' "$f"
    [ "$status" -ne 0 ]
  done
  diff -q "$ASEED/mcp.json" "$ASTOW/mcp.json"
}

# ── ticket 04: default theme Catppuccin Mocha Sapphire ───────────────────────

@test "settings selects the noctalia theme (ADR 0128)" {
  grep -q '"theme": "noctalia"' "$SEED"
  grep -q '"theme": "noctalia"' "$STOW"
}

@test "noctalia.json is seeded Catppuccin Mocha Sapphire, 53+ tokens (ADR 0109)" {
  local f="$ASEED/themes/noctalia.json"
  [ -f "$f" ]
  grep -q '"name": "noctalia"' "$f"
  grep -q '"sapphire": "#74c7ec"' "$f"          # the accent var
  grep -q '"accent": "sapphire"' "$f"           # accent bound to sapphire
  grep -q '"thinkingHigh": "red"' "$f"          # default thinking level border
  grep -q '"bashMode":' "$f"                    # a late-section token is present
  # pi requires all 53 colour tokens — assert a generous floor
  [ "$(grep -cE '^[[:space:]]*"[a-zA-Z]+": ' "$f")" -ge 53 ]
}

@test "the theme file is seed-only: gitignored, never in the stow tree (0128)" {
  grep -q '^\.pi/agent/themes/' "$GI"
  [ ! -e "$ASTOW/themes/noctalia.json" ]
}

# ── ticket 05: live-follow via a Noctalia user-template ──────────────────────

@test "config.toml declares the pi user-template → pi's theme file (ADR 0128)" {
  grep -q '\[theme.templates.user.pi\]' "$CT"
  grep -q 'noctalia/templates/pi.json' "$CT"
  grep -qE 'output_path[[:space:]]*=.*\.pi/agent/themes/noctalia.json' "$CT"
}

@test "the pi template input maps Noctalia roles to pi's tokens (Mustache)" {
  [ -f "$TPL" ]
  grep -q '"name": "noctalia"' "$TPL"
  # Mustache role placeholders, e.g. accent ← primary
  grep -q '"accent": "{{colors.primary.default.hex}}"' "$TPL"
  # semantic colours come from the palette's terminal_* roles
  grep -q '"success": "{{colors.terminal_normal_green.default.hex}}"' "$TPL"
  grep -q '"error": "{{colors.error.default.hex}}"' "$TPL"
  # same 53+ token floor as the static seed
  [ "$(grep -cE '"[a-zA-Z]+": "\{\{colors\.' "$TPL")" -ge 53 ]
}
