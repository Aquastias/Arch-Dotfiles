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
  OPERATOR_USER="$REPO/.installer/users/aquastias/profile.jsonc"
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
  for package in claude-code bubblewrap socat github-cli ccusage npm; do
    grep -q "$package" "$INSTALL"
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
  local settings_file="$HOMESEED/settings.json"
  [ -f "$settings_file" ]
  [ "$(jq -r '.model' "$settings_file")" = "claude-opus-5-5" ]
  [ "$(jq -r '.fallbackModel[0]' "$settings_file")" = "claude-sonnet-5" ]
  [ "$(jq -r '.promptCacheTtl' "$settings_file")" = "3600" ]
  [ "$(jq -r '.permissions.defaultMode' "$settings_file")" = "auto" ]
  [ "$(jq -r '.permissions.disableBypassPermissionsMode' "$settings_file")" = "disable" ]
  [ "$(jq -r '.skipAutoPermissionPrompt' "$settings_file")" = "true" ]
  [ "$(jq -r '.attribution.commit' "$settings_file")" = "" ]
  [ "$(jq -r '.attribution.pr' "$settings_file")" = "" ]
  [ "$(jq -r '.attribution.sessionUrl' "$settings_file")" = "false" ]
  [ "$(jq -r '.sandbox.failIfUnavailable' "$settings_file")" = "true" ]
  jq -e '.sandbox.network.allowUnixSockets
    | index("/run/libvirt/libvirt-sock")' "$settings_file" >/dev/null
  [ "$(jq -r '.cleanupPeriodDays' "$settings_file")" = "30" ]
  [ "$(jq -r '.autoUpdatesChannel' "$settings_file")" = "stable" ]
}

# ── curated feature set: unused tooling off, current Opus (ADR 0142) ──────────

@test "seeded settings.json curates the feature set (ADR 0142)" {
  local settings_file="$HOMESEED/settings.json"
  [ "$(jq -r '.effortLevel' "$settings_file")" = "medium" ]
  [ "$(jq -r '.disableClaudeAiConnectors' "$settings_file")" = "true" ]
  [ "$(jq -r '.disableRemoteControl' "$settings_file")" = "true" ]
  [ "$(jq -r '.enableArtifact' "$settings_file")" = "false" ]
  [ "$(jq -r '.disableWorkflows' "$settings_file")" = "true" ]
  [ "$(jq -r '.syncClaudeAiSkills' "$settings_file")" = "false" ]
  [ "$(jq -r '.syncClaudeAiPlugins' "$settings_file")" = "false" ]
  [ "$(jq -r '.env.DISABLE_TELEMETRY' "$settings_file")" = "1" ]
  [ "$(jq -r '.env.DISABLE_ERROR_REPORTING' "$settings_file")" = "1" ]
}

# ── single source under the program home/ (ADR 0134) ─────────────────────────

@test "home/.claude is the single source: the seed files live here, +x kept" {
  for seed_file in settings.json CLAUDE.md scripts/statusline.sh \
    scripts/block-sleep-poll.sh; do
    [ -f "$HOMESEED/$seed_file" ]
  done
  [ -x "$HOMESEED/scripts/statusline.sh" ]
  [ -x "$HOMESEED/scripts/block-sleep-poll.sh" ]
}

# ── sleep-poll hook (ADR 0156) ───────────────────────────────────────────────

@test "seeded settings.json registers the sleep-poll PreToolUse hook" {
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]
    | select(.command == "~/.claude/scripts/block-sleep-poll.sh")' \
    "$HOMESEED/settings.json" >/dev/null
}

_sleep_hook() {
  jq -n --arg command "$1" --argjson background "${2:-false}" \
    '{tool_name:"Bash",
      tool_input:{command:$command, run_in_background:$background}}' \
    | "$HOMESEED/scripts/block-sleep-poll.sh"
}

@test "sleep-poll hook blocks a foreground sleep of 60 s or more" {
  run _sleep_hook 'sleep 240; tail task.output'
  [ "$status" -eq 2 ]
  run _sleep_hook 'cd x && sleep 2m'
  [ "$status" -eq 2 ]
}

@test "sleep-poll hook passes short sleeps and background tasks" {
  run _sleep_hook 'until ready; do sleep 5; done'
  [ "$status" -eq 0 ]
  run _sleep_hook 'sleep 600; make' true
  [ "$status" -eq 0 ]
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

@test "the operator user carries claude (ADR 0133)" {
  grep -qE '"claude"' "$OPERATOR_USER"
}

# ── doc correction ───────────────────────────────────────────────────────────

@test "CONTEXT.md records .claude as selectively tracked, not wholesale" {
  grep -q 'tracked' "$CONTEXT"
  grep -qE 'selectively.*settings\.json|scripts/statusline\.sh.*ADR 0133' \
    "$CONTEXT"
}
