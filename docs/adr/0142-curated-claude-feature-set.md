# ADR 0142: Curated Claude Code feature set

## Status
Accepted — implemented. Amends ADR 0133's settings choices. The served
`settings.json` (single source under the dev/claude program `home/`, ADR 0134)
disables the unused feature surface and pins the current Opus; the Matt Pocock
skill store is bootstrapped by the program's `install.sh`. Guarded by
`.installer/tests/config/claude-agent.bats`. No `CONTEXT.md` term changed.

## Context
Claude Code ships a large tooling surface, most of it unused here. A usage audit
(103 transcripts, 39 sessions, ~1 month) found the four claude.ai connectors
(Gmail, Calendar, Drive, Claude_Docs), Remote Control, Artifacts, and Workflows
fired essentially zero times; telemetry and error reporting ran despite the
operator's existing non-essential-traffic opt-out; the served model was pinned
to the superseded Opus 4.8; and nothing stopped claude.ai from syncing
skills/plugins outside the repo-controlled Matt Pocock set. ADR 0133 established
the served config but predates these settings keys and Opus 5.5.

## Decision
Trim the served config to what the operator actually uses, in the one source
file, and record the rationale so a later update re-enabling a feature is
caught.

| Feature | Decision | Why |
|---|---|---|
| Gmail / Calendar / Drive / Claude_Docs connectors | disable (`disableClaudeAiConnectors`) | 0 uses / 39 sessions |
| Remote Control | disable | unused; terminal workflow |
| Artifacts | disable (`enableArtifact: false`) | terminal workflow |
| Workflows | disable | none defined; 0 use |
| claude.ai skill/plugin sync | disable (`syncClaudeAi{Skills,Plugins}`) | keep skills repo-controlled |
| Telemetry / error reporting | disable (env `DISABLE_*`) | matches traffic opt-out |
| model | `claude-opus-5-5` | current recommended Opus (verified live + `/model`) |
| effortLevel | `medium` | Opus 5.5 native default |
| Matt Pocock skills (all) | keep + installer-owned | full workflow; reproducible |
| Grep / Glob | keep | unused but built-in, free |
| checkpointing / auto-compact / thinking / bg agents | keep | in active use |

Skills stay all-on: the operator uses a broad set, so pruning them buys only
listing noise. Instead the store is made reproducible — `install.sh` runs
`npx skills@latest add mattpocock/skills` (the Vercel `skills` CLI), a
regenerable runtime asset, not tracked config.

## Considered options
- **`disableBundledSkills` / `skillOverrides` to prune skills** — rejected: the
  operator uses the full set; the only cost was listing noise.
- **Vendor the skills into the repo** — rejected: third-party churn and
  machinery for no reproducibility gain over the CLI bootstrap.
- **Leave connectors as an account-only click** — rejected:
  `disableClaudeAiConnectors` is a user-scope key, so the decision is served and
  reproducible in-repo.
- **Keep Opus 4.8** — rejected: Opus 5.5 is the current recommended Opus,
  confirmed available on the account via `/model`.

## Consequences
- Fresh builds get the trimmed feature set and current Opus automatically; the
  operator's environment (sandbox, permissions, statusline, voice, background
  agents, checkpointing) is unchanged.
- The repo-root `.claude/settings.json` duplicate (ADR 0133/0134) should track
  the source, but in the dev sandbox it is a read-only bind-mount, so its sync
  happens outside the sandbox. The existing "duplicate retired" test tolerates
  the lingering file; no strict source==duplicate equality guard was added, as
  it could not be satisfied from within the sandbox.
- The skill store depends on `npm`/`npx` + network at install; an offline build
  skips the bootstrap (non-fatal) and the operator runs it later.
- A future Claude Code update that re-enables a disabled feature is caught by
  the `claude-agent.bats` assertions against the table above.
