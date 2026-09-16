#!/usr/bin/env bats
# Claude Code (ADR 0133). Static seam mirroring pi-agent.bats: assert the
# COMMITTED payload + program definition + package/profile wiring + stow
# gitignore shape, without running an install.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."      # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/claude"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  PAYLOAD="$PROG/payload"                 # bundled seed payload (.installer)
  STOW="$REPO/.claude"                    # repo-root hand-stow copy
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

@test "install.sh installs claude-code + sandbox/gh/ccusage deps" {
  [ -x "$INSTALL" ]
  grep -qE '\$\{AUR_HELPER\} -S --noconfirm --needed' "$INSTALL"
  for p in claude-code bubblewrap socat github-cli ccusage; do
    grep -q "$p" "$INSTALL"
  done
}

@test "install.sh seeds the payload and never writes .credentials.json" {
  local pat='cp -r "${PROGRAMS}/dev/claude/payload/\." "${HOME}/.claude/"'
  grep -q "$pat" "$INSTALL"
  run grep -qE '(cp|tee|>)[^#]*\.credentials\.json' "$INSTALL"
  [ "$status" -ne 0 ]
}

# ── seeded settings: the pinned keys (ADR 0133) ──────────────────────────────

@test "seeded settings.json pins the decided keys" {
  local s="$PAYLOAD/settings.json"
  [ -f "$s" ]
  [ "$(jq -r '.model' "$s")" = "claude-opus-4-8" ]
  [ "$(jq -r '.fallbackModel[0]' "$s")" = "claude-sonnet-5" ]
  [ "$(jq -r '.promptCacheTtl' "$s")" = "3600" ]
  [ "$(jq -r '.permissions.defaultMode' "$s")" = "auto" ]
  [ "$(jq -r '.permissions.disableBypassPermissionsMode' "$s")" = "true" ]
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

# ── seed ↔ stow parity (no drift) ────────────────────────────────────────────

@test "repo .claude stow copy is byte-identical to the seed payload" {
  for f in settings.json CLAUDE.md scripts/statusline.sh; do
    [ -f "$STOW/$f" ]
    diff -q "$PAYLOAD/$f" "$STOW/$f"
  done
}

# ── stow gitignore shape ─────────────────────────────────────────────────────

@test "exactly the three stow files are tracked under .claude" {
  run git -C "$REPO" ls-files .claude
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
  printf '%s\n' "$output" | grep -qx '.claude/settings.json'
  printf '%s\n' "$output" | grep -qx '.claude/CLAUDE.md'
  printf '%s\n' "$output" | grep -qx '.claude/scripts/statusline.sh'
}

@test "claude runtime state and credentials stay gitignored" {
  git -C "$REPO" check-ignore -q .claude/settings.local.json
  git -C "$REPO" check-ignore -q .claude/.credentials.json
  git -C "$REPO" check-ignore -q .claude/commands
  grep -q '^\.claude/\.credentials\.json' "$GI"
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
