# Claude Code shipped fleet-wide (seeded + stowable), reworked statusline

---
Status: accepted. Reuses the pi/kitty delivery pattern (ADR 0127/0130) and the
seed-never-stow contract (ADR 0095); statusline colors fold into ANSI-16
cohesion (ADR 0132).
---

Claude Code is the fleet's coding agent but was **never provisioned by the
repo** — installed by hand, configured ad-hoc, its `~/.claude/` outside version
control. pi and kitty already seed **and** stow their config (ADR 0127/0130);
Claude Code did not. We want it installed at build time, its config seeded and
hand-stowable, and its statusline reworked to read the data Claude Code now
exposes natively.

## Decision

**Delivery — a new `dev/claude` [[User Program]].** Mirrors `dev/pi`
(`kind: user`, installed by the [[Program Runner]] in arch-chroot via the
[[AUR Helper]]). Owns the AUR package **`claude-code`** (canonical, 94-vote; no
`-bin` exists) plus the deps its features need: **`bubblewrap`** + **`socat`**
(the Bash sandbox is dead without them — upstream optdepends, but mandatory here
because the seeded config runs `sandbox.enabled: true`), **`github-cli`** (the
CLAUDE.md gh mandate), and **`ccusage`** (statusline usage detail, below).
`claude-code-seccomp` was considered and dropped. The program seeds the config
payload into `~/.claude/` (`cp -r`, mirroring pi); the installer **never stows**
(ADR 0095), and `.credentials.json` is **never seeded** — `/login` writes it
0600 on first run.

**Stow placement — gitignore-negation, not a new namespace.** Unlike `.pi/`,
repo-root `.dotfiles/.claude/` is **gitignored** *and* is where Claude Code
writes this repo's own project-state, so it cannot simply become a stow tree the
way pi's `.pi/` did. We **negate** `.gitignore` to track exactly
`.claude/{settings.json,CLAUDE.md,scripts/statusline.sh}` and nothing else, so
`stow --no-folding .` links those three into `~/.claude/` while the untracked
runtime state stays ignored. Accepted cost: when Claude runs *inside*
`~/.dotfiles`, that `settings.json` is read at both user and project scope —
harmless, identical content merges idempotently, and a gitignored
`.claude/settings.local.json` still carries any project-only override. This also
corrects a live doc bug: `CONTEXT.md` listed `.claude/` as a [[Stow Tree]] dir
while `.gitignore` excluded it entirely.

**Settings (`settings.json`) — notable non-default choices.** Attribution is
killed **structurally**, not just by prose: `attribution.commit` /
`attribution.pr` = `""`, `attribution.sessionUrl: false` — the CLAUDE.md "never
add Claude attribution" rule was previously only instructional. The sandbox
gains `network.allowUnixSockets` for the **libvirt socket**
(`/run/libvirt/libvirt-sock*`), so `vm.sh`/`virsh` run *sandboxed* instead of
needing the escape hatch `docs/agents/vm-sandbox.md` documents, plus
`failIfUnavailable: true`. Launch drops straight into **auto mode**
(`permissions.defaultMode: auto`, `skipAutoPermissionPrompt: true`) with
`disableBypassPermissionsMode: "disable"`. Also
`fallbackModel: ["claude-sonnet-5"]`, `promptCacheTtl: 3600` (1h),
`cleanupPeriodDays: 30`, `feedbackSurveyRate: 0`,
`preferredNotifChannel: "desktop"`, `autoUpdatesChannel: "stable"`,
`emojiCompletionEnabled: false`. Model stays Opus 4.8 (`claude-opus-4-8`).

**Statusline — native payload fields + emoji, ANSI-16.** The reworked
`scripts/statusline.sh` reads what Claude Code now exposes: the **5-hour
rate-limit meter** from `rate_limits.five_hour.used_percentage` (+ a `resets_at`
countdown) replaces the per-session `$cost` on subscription plans;
`prompt_cache.hit_ratio` replaces the fragile tail-the-transcript cache hack;
`effort.level` shows beside the model; `cost.total_lines_added/removed` render
as **green add / red delete**; and a **red dot** flags a dirty working tree
(`git status --porcelain`). **`ccusage`** supplies token/$ burn detail as a
*second* segment, run at most every ~30s into an mtime-checked tmp cache so it
**never blocks the prompt** (invoking it per render would re-parse all session
JSONL). Icons stay **emoji** — the Nerd-glyph swap was prototyped and
**rejected** (the operator preferred the colorful emoji). The script's colors
fold into the ANSI-16 TUI cohesion set (ADR 0132), which it was an outlier to.

## Considered options

- **A `-bin` package like pi** — none exists; `claude-code` is the canonical AUR
  package, installed directly.
- **ccusage as the primary % meter** — rejected: it re-parses all session JSONL
  per render (prompt latency) and yields tokens/$, not a clean %, without a
  hardcoded plan cap. The native `rate_limits` field is free, instant, already a
  %. ccusage survives only as a cached burn-detail segment.
- **`ccusage-statusline-rs`** (a prebuilt Rust Claude-Code statusline, on the
  AUR) — rejected: usage-only, it would drop the sandbox/plan/dirty/model
  segments the custom statusline provides. Plain `ccusage` (AUR) feeds the
  cached burn segment instead.
- **Nerd-Font statusline glyphs** — approved in principle, then rejected at the
  prototype: emoji render everywhere and read better here.
- **A separate stow namespace (not `.claude/`)** — cleaner project/user
  separation but breaks the repo's one-command `stow .`; the harmless
  double-read is the cheaper trade.
- **`/etc/skel` seed like kitty** — the more correct multi-user route, but the
  box is single-user, so the pi-style `cp -r ~/.claude` stays consistent.

## Consequences

- Claude Code installs and is configured on every fresh build; the operator
  hand-stows the repo copy as with pi/kitty.
- `~/.claude/settings.json` now serves double duty (user + dotfiles-project
  scope); project-only tweaks must go in the gitignored
  `.claude/settings.local.json`.
- New fleet surface: a `dev/claude` program, a negated `.gitignore` block, a
  tracked `.claude/` stub (3 files), and a `CONTEXT.md` fix. A drift test should
  guard the seed payload ↔ repo `.claude/` (as `pi-agent.bats` does).
- The statusline depends on `ccusage` and `jq`; a box without ccusage shows the
  native meter only (the cached segment stays empty), degrading gracefully.
- `.credentials.json` is never committed/seeded — `/login` per machine, the same
  hands-on contract as pi's auth.
