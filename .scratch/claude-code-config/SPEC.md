# Spec: Claude Code as a fleet-served, configured, stow-ready agent

Status: ready-for-agent

Anchored by [[ADR 0133]] (Claude Code fleet-wide, seeded + stowable, reworked
statusline). Reuses the pi/kitty delivery pattern (ADR 0127/0130), the
seed-never-stow contract (ADR 0095), and the ANSI-16 TUI cohesion (ADR 0132).

## Problem Statement

The operator runs Claude Code as their coding agent on desktop and laptop, but
it is the one tool the repo never provisions: installed by hand, configured
ad-hoc, and its whole `~/.claude/` left outside version control. pi and kitty
already seed **and** stow their config; Claude Code does not, so a fresh box has
no agent, no curated settings, and a stock statusline. The existing statusline
also predates the fields Claude Code now exposes — it tails the transcript to
guess a cache-hit rate and shows no plan-usage at all.

## Solution

Ship Claude Code fleet-wide as a new `dev/claude` [[User Program]] with a full,
stow-ready `~/.claude/` config that is also seeded at install time. The agent
comes pre-loaded with a curated `settings.json` (sandbox on, auto mode on,
attribution off, libvirt-aware), a reworked statusline that reads Claude Code's
native payload fields (5-hour rate-limit meter, cache-hit ratio, effort, dirty
tree, lines +/-) plus a cached `ccusage` burn detail, and the fleet's global
`CLAUDE.md`. The installer seeds but **never stows**; the operator hand-stows
the repo copy. Auth stays a per-machine `/login`; no token is ever committed.

## User Stories

1. As a desktop/laptop user, I want Claude Code installed automatically, so that
   I don't hand-install my agent on every machine.
2. As the operator, I want Claude Code served from the core layer the way pi is,
   so that desktop and laptop (which share all software) get it from one place.
3. As a user, I want the sandbox's real dependencies installed with the agent,
   so that `sandbox.enabled: true` actually works out of the box.
4. As a user, I want `github-cli` present, so that Claude Code honors my
   CLAUDE.md "use gh" mandate with no extra step.
5. As the operator, I want the full config present on a fresh install with no
   network, so that a freshly imaged box is usable offline (bar `/login`).
6. As the operator, I want the config also stow-ready in the dotfiles repo, so
   that I can stow it by hand like my other dotfiles.
7. As the operator, I want the installer to seed but **never stow**, so that
   stow stays my manual, operator-owned action (ADR 0095).
8. As a security-conscious operator, I want `.credentials.json` kept out of the
   repo and never seeded, so that no auth token is ever committed or stowed.
9. As a user, I want to sign in once per machine via `/login`, so that I use my
   existing Claude Max subscription without managing an API key.
10. As a user, I want Claude Code to default to Opus 4.8, so that my agent runs
    the most capable model by default.
11. As a user, I want a Sonnet fallback when Opus is overloaded, so that a busy
    model never dead-ends my session.
12. As a user, I want a 1-hour prompt-cache TTL, so that my cache stays warm
    across longer gaps and my cache-hit statusline reads higher.
13. As a user, I want Claude Code to open straight in auto mode with no
    per-launch notice, so that every fresh session is immediately productive.
14. As a security-conscious operator, I want full bypass-permissions mode
    disabled, so that a seeded box can never drop all guardrails.
15. As an operator who forbids Claude attribution, I want the no-attribution
    rule enforced **structurally** in settings, so that it does not rely on the
    model obeying prose in CLAUDE.md.
16. As a user who drives VMs, I want the sandbox to reach the libvirt socket, so
    that `vm.sh`/`virsh` run *inside* the sandbox instead of forcing me to
    disable it (the friction in `docs/agents/vm-sandbox.md`).
17. As a user, I want the sandbox to fail loudly if it can't start, so that I
    never silently run unsandboxed.
18. As a privacy-leaning operator, I want a 30-day transcript retention and the
    feedback survey off, so that local history and nagging stay minimal.
19. As a Linux user with a notification daemon, I want desktop notifications, so
    that agent/input-needed alerts use notify-send.
20. As an operator who wants a reproducible fleet, I want the stable update
    channel, so that machines track the same Claude Code releases.
21. As a user, I want the emoji-completion `:shortcode:` noise off, so that my
    terminal input stays clean.
22. As a user, I want my global `CLAUDE.md` version-controlled and stowed, so
    that my standing instructions ride to every machine.
23. As a user, I want the statusline to show my 5-hour usage as a colored meter
    with a reset countdown, so that I can see how much of my window is left.
24. As a user on a subscription, I want the 5-hour meter to replace the
    per-session dollar figure, so that the bar shows the number that matters to
    me (cost is noise on a subscription).
25. As an API-billed user, I want the dollar figure shown instead, so that the
    bar stays meaningful when usage *is* billed.
26. As a user, I want the cache-hit rate read from the native `prompt_cache`
    field, so that it is accurate and the statusline stops tailing my
    transcript on every render.
27. As a user, I want my reasoning effort shown beside the model, so that I can
    see at a glance whether I'm on high effort.
28. As a user, I want added lines green and deleted lines red, so that churn
    reads correctly at a glance.
29. As a user, I want a red dot by the branch when the working tree is dirty, so
    that I never forget uncommitted changes.
30. As a user, I want token/dollar burn detail from `ccusage`, so that I can see
    my current 5-hour block spend.
31. As a user, I want the `ccusage` detail cached (refreshed at most every
    ~30s), so that the statusline never blocks my prompt re-parsing session
    files.
32. As a user, I want the statusline to keep emoji icons, so that segments read
    clearly and render on every box (the Nerd-glyph swap was rejected at
    prototype).
33. As a user, I want the statusline colors on the ANSI-16 palette, so that it
    tracks my kitty theme with the rest of my TUIs (ADR 0132).
34. As a user without `ccusage`, I want the statusline to still show the native
    meter, so that a missing tool degrades gracefully rather than breaking.
35. As the operator, I want the `CONTEXT.md` mis-listing of `.claude/` as a
    stow-tree dir corrected, so that the glossary matches the real `.gitignore`.
36. As the operator, I want the whole setup verifiable in a VM, so that I trust
    it before it reaches hardware.
37. As the operator, I want the static config verifiable in bats tests, so that
    packaging/stow/settings/statusline regressions are caught cheaply.

## Implementation Decisions

- **New Program `dev/claude`** (`kind: user`), installed by the
  [[Program Runner]] inside arch-chroot via the [[AUR Helper]]. Owns the AUR
  package **`claude-code`** (canonical; no `-bin` exists) and pulls
  **`bubblewrap`**, **`socat`** (sandbox runtime — upstream optdepends, but
  mandatory here), **`github-cli`**, and **`ccusage`**. `claude-code-seccomp`
  was considered and dropped.
- **Fleet placement in [[User Core]]'s `programs`**, alongside `pi`, mirroring
  the fleet-served precedent (ADR 0114/0127), so every user on every
  core-resolved host receives Claude Code from one place. `claude` is appended
  to that shared `programs` list (where `pi` already lives), not a per-host
  profile.
- **Dual config delivery.** The `~/.claude/` payload is **seeded** into the
  owning user's `$HOME` by the program (`cp -r`, the pi shape) **and** present
  as a **stow-ready** package at the dotfiles repo root. The installer seeds
  only; it never stows (ADR 0095) — the operator stows.
- **Stow placement via gitignore-negation.** Repo-root `.claude/` is gitignored
  *and* is Claude Code's own project-state dir, so it cannot become a plain
  stow tree like `.pi/`. `.gitignore` is **negated** to track exactly
  `.claude/settings.json`, `.claude/CLAUDE.md`, and `.claude/scripts/
  statusline.sh` — nothing else — so `stow --no-folding .` links those three
  into `~/.claude/` while runtime state stays ignored. Accepted overlap: run
  inside `~/.dotfiles`, `settings.json` is read at both user and project scope
  (idempotent); project-only tweaks go in a gitignored
  `.claude/settings.local.json`.
- **Auth.** Claude Max via `/login`, once per machine. `.credentials.json`
  (0600) is gitignored, never seeded or stowed.
- **Curated `settings.json`** (seeded verbatim, paths are fleet-uniform). Model
  `claude-opus-4-8`; `fallbackModel: ["claude-sonnet-5"]`; `promptCacheTtl:
  3600`; `permissions.defaultMode: auto` + `skipAutoPermissionPrompt: true` +
  `disableBypassPermissionsMode: true`; `attribution.commit`/`attribution.pr`
  = `""`, `attribution.sessionUrl: false`; sandbox `network.allowUnixSockets`
  for `/run/libvirt/libvirt-sock*` + `failIfUnavailable: true` (existing
  filesystem block retained); `cleanupPeriodDays: 30`; `feedbackSurveyRate: 0`;
  `preferredNotifChannel: "desktop"`; `autoUpdatesChannel: "stable"`;
  `emojiCompletionEnabled: false`. `settings.local.json` and `.credentials.json`
  are never touched. Both undocumented `voice.{enabled,mode}` and the flat
  `voiceEnabled` are seeded **verbatim** — neither is in the documented settings
  surface and voice already works, so we don't guess which the CLI reads.
- **Reworked statusline** (`scripts/statusline.sh`). Reads native payload
  fields: `rate_limits.five_hour.used_percentage` + `resets_at` (a colored
  5-hour meter that replaces `$cost` on subscription plans; `$cost` stays on
  API plans), `prompt_cache.hit_ratio` (replacing the transcript-tail hack),
  `effort.level` (beside the model), `cost.total_lines_added/removed` (green
  add / red delete). A **red dot** flags a dirty tree via `git status
  --porcelain`. Icons stay **emoji**; colors are ANSI-16 (ADR 0132). `ccusage`
  provides a *second* burn-detail segment, run at most every ~30s into an
  mtime-checked tmp cache so it never blocks the prompt; absent `ccusage`, the
  segment is empty and the native meter still renders.
- **`CONTEXT.md` fix.** Remove/repair the entry listing `.claude/` as a
  [[Stow Tree]] dir, which contradicted `.gitignore`.

## Testing Decisions

Good tests assert **external behavior** — the resolved configuration, the
materialized stow tree, the shape of shipped files, statusline output, live VM
behavior — never private shell functions.

- **Static seam — new `claude-agent.bats`** (`.installer/tests/config/`,
  modeled on `pi-agent.bats`/`noctalia-stow.bats`). Asserts, without a real
  install: the `dev/claude` program config validates and is wired into desktop
  + laptop; `claude-code` + `bubblewrap` + `socat` + `github-cli` + `ccusage`
  resolve; the stow tree carries the three tracked files with the pinned
  settings keys (attribution empty, `defaultMode: auto`, libvirt socket,
  `claude-opus-4-8`); `.gitignore` tracks exactly those three and still excludes
  `.credentials.json` + runtime state; the seed payload
  (`.installer/programs/dev/claude/`) is **byte-identical** to the stow copy
  (`.claude/`), drift-guarded as `pi-agent.bats` does for pi; and `CONTEXT.md`
  no longer mis-lists `.claude/`. Prior art: `pi-agent.bats`,
  `noctalia-stow.bats`, `packages.bats`, `profiles-aur.bats`.
- **Statusline seam — new `statusline.bats`** (the one new seam, justified: the
  statusline is a pure JSON→string function). Pipes fixture payloads (clean,
  dirty, near-limit, subscription, API) into `statusline.sh` and asserts the
  segments: the 5h-meter↔`$cost` swap by billing, the native cache ratio,
  effort, the dirty red dot, +green/−red lines, and emoji icons. The approved
  `.scratch/claude-code-config/` prototype already encodes the expected shape.
- **Behavioral seam — VM via `vm-agent.sh`** on the `arch-combined`
  [[Agent-Controllable VM]] (existing harness, no new infra): `claude` is on
  PATH; the sandbox starts (bwrap/socat present); a `virsh`/`vm.sh` call
  succeeds *inside* the sandbox via the `allowUnixSockets` rule; the statusline
  renders. Prior art: `flow-persistent.bats`, `vm-agent.bats`, `vm-cli.bats`.

## Out of Scope

- Replacing or aliasing pi with Claude Code, or vice versa — both stay reachable
  by their own names.
- Seeding any MCP servers for Claude Code — none are shipped; servers are added
  per-project via `.mcp.json` (`enableAllProjectMcpServers` stays false).
- Seeding a custom `outputStyle`, `commands/`, `agents/`, `hooks/`, or `rules/`
  — only `settings.json`, `CLAUDE.md`, and the statusline are versioned for now.
- Automating `/login` — auth is a deliberate per-machine manual step.
- `/etc/skel` seeding (kitty's multi-user route) — the box is single-user, so
  the pi-style `cp -r ~/.claude` is used.
- Enterprise/managed, cloud-auth (Bedrock/GCP), Remote Control, and IDE settings
  — not applicable to this single-user Arch fleet.

## Further Notes

- `ccusage` ships from the **AUR** (`ccusage`, v20.0.20 — `kind: user`/paru,
  like the rest); no npm path is needed. `ccusage-statusline-rs` (a prebuilt
  Rust Claude-Code statusline) was considered and rejected: it is usage-only and
  would drop the sandbox/plan/dirty/model segments the custom statusline adds.
- `defaultModel` / `fallbackModel` are pinned ids that drift as models ship;
  bumping the default means editing `settings.json`.
- The statusline reworks the existing script rather than replacing it; the
  transcript-tail cache block is deleted, and the sandbox/plan/branch segments
  are retained.
- The approved statusline prototype lives at
  `.scratch/claude-code-config/` as a throwaway primary source (an `emoji` and a
  `nerd` icon set; `emoji` won).
- A default-model or settings change now lives in one more seed point (the
  program payload) beside the repo stow copy — a drift test keeps them
  byte-identical, as `pi-agent.bats` does for pi.
