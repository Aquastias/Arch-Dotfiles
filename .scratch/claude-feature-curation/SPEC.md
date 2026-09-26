# Curated Claude Code feature set: disable unused tooling, pin Opus 5.5

Status: ready-for-agent

Curate the fleet-wide Claude Code config down to what the operator actually
uses: disable unused built-in tooling, pin the current model, and make the
Matt Pocock skill store installer-owned. Extends the [[dev/claude]] [[User
Program]] and its single-source config (ADR 0133/0134). Grounded in a usage
audit (39 sessions, ~1mo) + the live model docs.

## Problem Statement

Claude Code ships a large tooling surface, most of which the operator never
uses. A usage audit over 39 sessions (~1 month) found: the four claude.ai
connectors (Gmail, Calendar, Drive, Claude_Docs) fired **zero** times; Remote
Control, Artifacts, and Workflows are unused; and telemetry/error-reporting run
despite the operator already disabling non-essential traffic. The served model
is pinned to Opus 4.8 while Opus 5.5 (the current recommended Opus) has shipped.
Nothing curbs claude.ai from syncing skills/plugins that would land outside the
repo's control. The operator wants one curated, reproducible config served the
same way the rest of the fleet config is — seeded at install, stowable day-2 —
not a pile of manual toggles that drift per machine.

## Solution

Curate the single-source `settings.json` under the [[dev/claude]] program
`home/.claude/` so a fresh build (and any re-stow) gets the trimmed feature set
automatically: unused built-in features off, `claude-opus-5-5` at `medium`
effort, telemetry off, and claude.ai skill/plugin sync off. Keep every feature
the operator does use (sandbox, permissions, statusline, voice, background
agents, checkpointing, all skills). Make the Matt Pocock skill store
installer-owned so "keep all skills" survives a rebuild. Record the
keep/disable rationale in an ADR so a future Claude update re-enabling something
does not silently undo the choices.

## User Stories

1. As an operator, I want the four unused claude.ai connectors disabled by the
   served config, so that my session tool listing is not padded with Gmail,
   Calendar, Drive, and Claude_Docs tools I never call.
2. As an operator, I want a single config key to kill all connectors, so that
   the decision is one tracked line, not a per-connector account click.
3. As an operator, I want Remote Control disabled, so that a feature I never use
   is not active on the machine.
4. As an operator, I want Artifacts disabled, so that my terminal-only workflow
   is not offered an output surface it never uses.
5. As an operator, I want Workflows disabled, so that an unused subsystem stops
   consuming attention and surface.
6. As an operator, I want telemetry and error reporting disabled in the served
   config, so that the config is consistent with the non-essential-traffic
   opt-out already present.
7. As an operator, I want the served model pinned to `claude-opus-5-5`, so that
   fresh builds run the current recommended Opus, not the superseded Opus 4.8.
8. As an operator, I want the served effort level at `medium`, so that the model
   runs at its own default effort instead of the previous `high`.
9. As an operator, I want the Sonnet 5 fallback retained, so that model
   fallback still works when Opus is unavailable.
10. As an operator, I want claude.ai skill sync disabled, so that the account
    cannot inject skills outside my repo-controlled Matt Pocock set.
11. As an operator, I want claude.ai plugin sync disabled, so that plugins
    cannot appear outside my repo control.
12. As an operator, I want every Matt Pocock skill kept, so that my full
    grilling/spec/issue workflow stays available.
13. As an operator, I want the skill store installed and synced by the
    installer, so that a fresh machine gets the current skill roster
    reproducibly rather than by hand.
14. As an operator, I want my stale renamed skills (`to-prd`, `to-issues`)
    resolved to their current names (`to-spec`, `to-tickets`), so that my local
    store matches current upstream.
15. As an operator, I want the sandbox, permission allow/deny rules, and libvirt
    socket access untouched, so that my security posture is preserved.
16. As an operator, I want the custom statusline, voice mode, fullscreen TUI,
    and attribution-blanking untouched, so that my working environment is
    unchanged.
17. As an operator, I want background agents, file checkpointing, auto-compact,
    and adaptive thinking left enabled, so that the features I actively rely on
    keep working.
18. As an operator, I want the repo-root `.claude/settings.json` duplicate kept
    identical to the source, so that Claude running inside `.dotfiles` reads the
    same curated config at project scope.
19. As an operator, I want the curated feature decisions recorded in an ADR with
    a disposition table, so that a future Claude update re-enabling a feature is
    caught against a written rationale.
20. As an operator, I want the change guarded by the existing claude test seam,
    so that a regression (a re-enabled feature, a wrong model string) fails the
    suite.
21. As an operator, I want the local machine's drifted `acceptEdits` mode
    reconciled to the source `auto`, so that the served default actually takes
    effect.
22. As a Claude session, I want the curated `settings.json` to remain valid
    JSON with only real, documented keys, so that the harness does not reject it
    on launch.

## Implementation Decisions

- **Single source of truth is the program home.** All settings edits land in
  `.installer/programs/dev/claude/home/.claude/settings.json` (ADR 0134). The
  [[Config Apply]] pass seeds it and `stow-configs.sh` stows it; `install.sh`
  stays package-only.
- **Repo-root duplicate stays byte-identical.** `.claude/settings.json` (the
  bind-mounted repo-root copy that lingers per ADR 0134) receives the same edits
  so the user+project double-read stays consistent.
- **Connectors.** Add `disableClaudeAiConnectors: true` (a documented
  security-key setting valid in user scope; disables all four connectors at
  once — no per-connector control exists).
- **Behavior toggles.** Add `disableRemoteControl: true`,
  `enableArtifact: false`, `disableWorkflows: true`.
- **claude.ai sync.** Add `syncClaudeAiSkills: false`,
  `syncClaudeAiPlugins: false`. These gate account-level sync only; they do not
  affect the local Matt Pocock skills (symlinks managed by the external
  manager).
- **Model + effort.** Set `model: "claude-opus-5-5"` (verified live against
  `platform.claude.com`, alias identical; account access confirmed by the
  operator via `/model`), `effortLevel: "medium"`. Keep
  `fallbackModel: ["claude-sonnet-5"]`.
- **Telemetry.** Extend the `env` block with `DISABLE_TELEMETRY: "1"` and
  `DISABLE_ERROR_REPORTING: "1"` alongside the existing
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`.
- **Untouched keys.** Sandbox, permissions, `statusLine`, `voice`,
  `autoMemoryEnabled: false`, `tui`, attribution, `cleanupPeriodDays`,
  `promptCacheTtl`, `autoUpdatesChannel`, `emojiCompletionEnabled`,
  `skipAutoPermissionPrompt`, `disableBypassPermissionsMode` all stay as-is.
  `defaultMode` is already `auto` in the source; no change (live drift is
  reconciled by re-stow, not an edit).
- **Skills — installer-owned, keep all.** `install.sh` gains a guarded bootstrap
  step running `npx skills@latest add mattpocock/skills` (the Vercel `skills`
  CLI, run as the owning user), which populates `~/.agents/skills` and writes
  `~/.skill-lock.json` from current upstream — resolving the
  `to-prd`→`to-spec` / `to-issues`→`to-tickets` renames for free. Requires
  `nodejs` + `npm` (for `npx`); add `npm` to the program deps if the
  `claude-code` package does not already pull it. The skill store is a
  regenerable runtime asset (never tracked, like a package), so bootstrapping it
  in `install.sh` is consistent with the package-only rule (ADR 0134); the
  reviewer should confirm this placement versus a dedicated post-install step.
  No `skillOverrides`; all skills are kept.
- **ADR.** Author `docs/adr/0142-curated-claude-feature-set.md` with a
  disposition table (feature → keep/disable → why), amending ADR 0133's
  settings choices.

## Testing Decisions

- **A good test asserts external behavior of the committed config**, not
  implementation detail: it checks that the served `settings.json` pins the
  decided values and that runtime/secret files stay ignored — never how the file
  was produced.
- **One existing seam, extended.** `.installer/tests/config/claude-agent.bats`
  is the static seam (asserts the committed payload without running an install).
  Extend its "pinned keys" test to assert: `model == "claude-opus-5-5"`,
  `effortLevel == "medium"`, `disableClaudeAiConnectors == true`,
  `disableRemoteControl == true`, `enableArtifact == false`,
  `disableWorkflows == true`, `syncClaudeAiSkills == false`,
  `syncClaudeAiPlugins == false`, and both `DISABLE_*` env vars present.
- **New drift guard.** Add a test asserting the repo-root `.claude/settings.json`
  equals the source `home/.claude/settings.json` byte-for-byte, so the duplicate
  cannot silently diverge.
- **Skill-manager wiring.** Extend the same bats file to assert `install.sh`
  invokes `npx skills@latest add mattpocock/skills` and that `npm`/`nodejs` is
  present in the program deps.
- **Prior art.** `claude-agent.bats` itself and `pi-agent.bats` are the model
  for static payload assertions via `jq`. The `no-python.sh` gate must stay
  green (bash + jq only; no Python).

## Out of Scope

- Any change to sandbox, permission, statusline, voice, or attribution config.
- Vendoring the Matt Pocock skills into the dotfiles repo (they remain
  external, manager-owned symlinks; only the bootstrap is added).
- Disabling built-in tools the operator relies on (Grep/Glob are unused but
  built-in and effectively free; not disabled).
- Enabling any new feature; this is a subtractive curation plus a model bump.
- Migrating the operator's live machine state beyond re-stowing from source.

## Further Notes

Disposition table (to be carried into ADR 0142):

| Feature | Decision | Why |
|---|---|---|
| Gmail / Calendar / Drive / Claude_Docs connectors | disable | 0 uses / 39 sessions |
| Remote Control | disable | unused; terminal workflow |
| Artifacts | disable | terminal workflow |
| Workflows | disable | none defined; 0 use |
| claude.ai skill/plugin sync | disable | keep skills repo-controlled |
| Telemetry / error reporting | disable | matches traffic opt-out |
| model | `claude-opus-5-5` | current recommended Opus (verified live) |
| effortLevel | `medium` | Opus 5.5 native default |
| Matt Pocock skills (all) | keep + installer-owned | full workflow; reproducible |
| Grep / Glob | keep | unused but built-in, free |
| checkpointing / auto-compact / thinking / bg agents | keep | in active use |

Audit basis: usage report over 103 transcripts / 39 sessions; model verified at
`platform.claude.com/docs/en/about-claude/models/overview` (Opus 5.5,
`claude-opus-5-5`, default effort `medium`).

Resolved during grilling: the skill-store bootstrap is `npx skills@latest add
mattpocock/skills` (the Vercel `skills` CLI) — `setup-matt-pocock-skills` is a
per-repo config scaffolder, not the store installer. Account access to
`claude-opus-5-5` confirmed by the operator via `/model` on an updated Claude
Code. No open questions remain.
