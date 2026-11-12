#!/usr/bin/env bats
# Claude Code (ADR 0133). Static seam mirroring pi-agent.bats: assert the
# COMMITTED payload + program definition + package/profile wiring + stow
# gitignore shape, without running an install.

load ../lib/json-helpers
load ../lib/text-helpers

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
  file_satisfies "$settings_file" '.model == "claude-opus-5-5"'
  file_satisfies "$settings_file" '.fallbackModel[0] == "claude-sonnet-5"'
  file_satisfies "$settings_file" '.promptCacheTtl == 3600'
  file_satisfies "$settings_file" '.permissions.defaultMode == "auto"'
  file_satisfies "$settings_file" '.permissions.disableBypassPermissionsMode == "disable"'
  file_satisfies "$settings_file" '.skipAutoPermissionPrompt == true'
  file_satisfies "$settings_file" '.attribution.commit == ""'
  file_satisfies "$settings_file" '.attribution.pr == ""'
  file_satisfies "$settings_file" '.attribution.sessionUrl == false'
  file_satisfies "$settings_file" '.sandbox.failIfUnavailable == true'
  file_satisfies "$settings_file" \
    '.sandbox.network.allowUnixSockets | index("/run/libvirt/libvirt-sock")'
  file_satisfies "$settings_file" '.cleanupPeriodDays == 30'
  file_satisfies "$settings_file" '.autoUpdatesChannel == "stable"'
}

# ── curated feature set: unused tooling off, current Opus (ADR 0142) ──────────

@test "seeded settings.json curates the feature set (ADR 0142)" {
  local settings_file="$HOMESEED/settings.json"
  file_satisfies "$settings_file" '.effortLevel == "medium"'
  file_satisfies "$settings_file" '.disableClaudeAiConnectors == true'
  file_satisfies "$settings_file" '.disableRemoteControl == true'
  file_satisfies "$settings_file" '.enableArtifact == false'
  file_satisfies "$settings_file" '.disableWorkflows == true'
  file_satisfies "$settings_file" '.syncClaudeAiSkills == false'
  file_satisfies "$settings_file" '.syncClaudeAiPlugins == false'
  file_satisfies "$settings_file" '.env.DISABLE_TELEMETRY == "1"'
  file_satisfies "$settings_file" '.env.DISABLE_ERROR_REPORTING == "1"'
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
  file_satisfies "$HOMESEED/settings.json" \
    '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]
    | select(.command == "~/.claude/scripts/block-sleep-poll.sh")'
}

_sleep_hook() {
  local call='{tool_name:"Bash",'
  call+=' tool_input:{command:$command, run_in_background:$background}}'
  # A Bash tool call, fed to the hook.
  jq -n --arg command "$1" --argjson background "${2:-false}" "$call" \
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
  ! text_has_line "$output" '.claude/CLAUDE.md'
  ! text_has_line "$output" '.claude/scripts/statusline.sh'
  local tracked
  for tracked in "${lines[@]}"; do
    [ "$tracked" = '.claude/settings.json' ]
  done
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
