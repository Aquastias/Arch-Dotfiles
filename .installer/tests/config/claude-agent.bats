#!/usr/bin/env bats
# Claude Code (ADR 0133). Static seam mirroring pi-agent.bats: assert the
# COMMITTED payload + program definition + package/profile wiring + stow
# gitignore shape, without running an install.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."      # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/claude"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOMESEED="$PROG/home/.claude"           # single-source config (ADR 0134)
  STOW="$REPO/.claude"                    # repo-root (3 tracked files retired)
  UCORE="$REPO/.installer/users/core/profile.jsonc"
  GI="$REPO/.gitignore"
  CONTEXT="$REPO/CONTEXT.md"
}

# ── program definition ───────────────────────────────────────────────────────

@test "dev/claude config.jsonc declares the user-kind claude program" {
  [ -f "$CFG" ]
  grep -q '"name": "claude"' "$CFG"
  grep -q '"kind": "user"' "$CFG"
}

@test "install.sh installs claude-code + sandbox/gh/ccusage/npm deps" {
  [ -x "$INSTALL" ]
  grep -qE '\$\{AUR_HELPER\} -S --noconfirm --needed' "$INSTALL"
  for p in claude-code bubblewrap socat github-cli ccusage npm; do
    grep -q "$p" "$INSTALL"
  done
}

@test "install.sh bootstraps the Matt Pocock skill store (skills CLI)" {
  # ADR 0142: the skill store is a regenerable runtime asset seeded via npx.
  grep -qE 'npx .*skills@latest add mattpocock/skills' "$INSTALL"
}

@test "install.sh does NOT seed config and never writes .credentials.json" {
  # ADR 0134: the Config Apply pass places home/.claude/; install.sh is
  # package-only and touches no $HOME config.
  ! grep -qE 'cp -r "\$\{PROGRAMS\}/dev/claude/payload' "$INSTALL"
  ! grep -qE 'cp[^#]*"\$\{HOME\}/\.claude' "$INSTALL"
  run grep -qE '(cp|tee|>)[^#]*\.credentials\.json' "$INSTALL"
  [ "$status" -ne 0 ]
}

# ── seeded settings: the pinned keys (ADR 0133) ──────────────────────────────

@test "seeded settings.json pins the decided keys" {
  local s="$HOMESEED/settings.json"
  [ -f "$s" ]
  [ "$(jq -r '.model' "$s")" = "claude-opus-5-5" ]
  [ "$(jq -r '.fallbackModel[0]' "$s")" = "claude-sonnet-5" ]
  [ "$(jq -r '.promptCacheTtl' "$s")" = "3600" ]
  [ "$(jq -r '.permissions.defaultMode' "$s")" = "auto" ]
  [ "$(jq -r '.permissions.disableBypassPermissionsMode' "$s")" = "disable" ]
  [ "$(jq -r '.skipAutoPermissionPrompt' "$s")" = "true" ]
  [ "$(jq -r '.attribution.commit' "$s")" = "" ]
  [ "$(jq -r '.attribution.pr' "$s")" = "" ]
  [ "$(jq -r '.attribution.sessionUrl' "$s")" = "false" ]
  [ "$(jq -r '.sandbox.failIfUnavailable' "$s")" = "true" ]
  jq -e '.sandbox.network.allowUnixSockets
    | index("/run/libvirt/libvirt-sock")' "$s" >/dev/null
  [ "$(jq -r '.cleanupPeriodDays' "$s")" = "30" ]
  [ "$(jq -r '.autoUpdatesChannel' "$s")" = "stable" ]
}

# ── curated feature set: unused tooling off, current Opus (ADR 0142) ──────────

@test "seeded settings.json curates the feature set (ADR 0142)" {
  local s="$HOMESEED/settings.json"
  [ "$(jq -r '.effortLevel' "$s")" = "medium" ]
  [ "$(jq -r '.disableClaudeAiConnectors' "$s")" = "true" ]
  [ "$(jq -r '.disableRemoteControl' "$s")" = "true" ]
  [ "$(jq -r '.enableArtifact' "$s")" = "false" ]
  [ "$(jq -r '.disableWorkflows' "$s")" = "true" ]
  [ "$(jq -r '.syncClaudeAiSkills' "$s")" = "false" ]
  [ "$(jq -r '.syncClaudeAiPlugins' "$s")" = "false" ]
  [ "$(jq -r '.env.DISABLE_TELEMETRY' "$s")" = "1" ]
  [ "$(jq -r '.env.DISABLE_ERROR_REPORTING' "$s")" = "1" ]
}

# ── single source under the program home/ (ADR 0134) ─────────────────────────

@test "home/.claude is the single source: the 3 files live here, +x preserved" {
  for f in settings.json CLAUDE.md scripts/statusline.sh; do
    [ -f "$HOMESEED/$f" ]
  done
  [ -x "$HOMESEED/scripts/statusline.sh" ]
}

@test "repo-root .claude/settings.json stays identical to the source (ADR 0142)" {
  # The lingering repo-root duplicate (read at project scope inside .dotfiles)
  # must not drift from the single source. Synced outside the dev sandbox, where
  # it is a read-only bind-mount.
  cmp -s "$STOW/settings.json" "$HOMESEED/settings.json"
}

@test "the repo-root .claude stow duplicate is retired (moved to home/)" {
  # ADR 0134: the tracked files moved into the program home/. CLAUDE.md +
  # scripts/statusline.sh are gone from repo-root .claude; settings.json is a
  # bind-mount in the dev sandbox (Device or resource busy), so its de-dup lands
  # outside it — the only file that may linger. The operator's gitignored
  # runtime .claude is untouched.
  run git -C "$REPO" ls-files .claude
  ! grep -qx '.claude/CLAUDE.md' <<<"$output"
  ! grep -qx '.claude/scripts/statusline.sh' <<<"$output"
  [ -z "$(grep -vx '.claude/settings.json' <<<"$output" | grep .)" ]
}

@test "claude runtime state and credentials stay gitignored" {
  git -C "$REPO" check-ignore -q .claude/settings.local.json
  git -C "$REPO" check-ignore -q .claude/.credentials.json
  git -C "$REPO" check-ignore -q .claude/commands
  grep -qE '^/?\.claude/\.credentials\.json' "$GI"
}

# ── package + profile wiring ─────────────────────────────────────────────────

@test "User Core serves claude fleet-wide (ADR 0133)" {
  grep -qE '"claude"' "$UCORE"
}

# ── doc correction ───────────────────────────────────────────────────────────

@test "CONTEXT.md records .claude as selectively tracked, not wholesale" {
  grep -q 'tracked' "$CONTEXT"
  grep -qE 'selectively.*settings\.json|scripts/statusline\.sh.*ADR 0133' \
    "$CONTEXT"
}
