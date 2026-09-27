# 01: Curated settings.json + test seam

**What to build:** The fleet-served Claude config disables the tooling the
operator never uses and runs the current Opus. On a fresh build (and any
re-stow) the seeded `settings.json` has the four claude.ai connectors off,
Remote Control / Artifacts / Workflows off, claude.ai skill+plugin sync off,
telemetry + error reporting off, `model: claude-opus-5-5` at `effortLevel:
medium`, with everything the operator uses (sandbox, permissions, statusline,
voice, background agents, checkpointing, auto-compact, thinking) untouched. The
change lands in the single source and its repo-root duplicate, and the existing
static test seam proves it.

Edits:
- `.installer/programs/dev/claude/home/.claude/settings.json` (single source,
  ADR 0134) — add `disableClaudeAiConnectors: true`,
  `disableRemoteControl: true`, `enableArtifact: false`,
  `disableWorkflows: true`, `syncClaudeAiSkills: false`,
  `syncClaudeAiPlugins: false`; set `model: "claude-opus-5-5"`,
  `effortLevel: "medium"`; extend `env` with `DISABLE_TELEMETRY: "1"` and
  `DISABLE_ERROR_REPORTING: "1"`. Keep `fallbackModel`, `defaultMode: auto`,
  and all other keys as-is.
- `.claude/settings.json` (repo-root bind-mounted duplicate) — apply the same
  edits so it stays byte-identical.
- `.installer/tests/config/claude-agent.bats` — extend the pinned-keys test to
  assert the new keys/values, and add a drift-guard test that repo-root
  `.claude/settings.json` equals the source byte-for-byte.

**Blocked by:** None (can start immediately).

**Status:** done

- [x] Source `settings.json` sets all six disable/sync keys, model, effort, and
      both `DISABLE_*` env vars; still valid JSON with only documented keys
- [x] Repo-root `.claude/settings.json` is byte-identical to the source
- [x] `claude-agent.bats` asserts each new key/value via `jq`
- [x] `claude-agent.bats` has a drift-guard test (repo-root == source)
- [x] `bats .installer/tests/config/claude-agent.bats` passes
- [x] `no-python.sh` gate stays green; no non-jq/bash tooling introduced
- [x] Operator note recorded: reconcile a live machine's `acceptEdits`→`auto`
      by re-stowing from source (one-time, not a repo change)

## Comments

- 2026-09-27 audit: 17aee35, bd078d6 (claude-agent.bats incl. repo-root drift
  guard; green 2026-09-27).
