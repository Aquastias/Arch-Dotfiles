# Pi coding agent shipped fleet-wide, seeded and stow-ready

---
Status: accepted.
---

We ship the **pi** coding agent (earendil-works/pi) as a second coding agent
alongside Claude Code, served to desktop + laptop. Because those two profiles
run identical software out of core (ADR 0114), pi goes into **core** — in the
spirit of the obs-studio addition, but since pi is a `kind: user` program the
fleet-wide lever is **User Core `programs`** (the per-user analogue of Host
Core's package list), not a host package. It therefore also reaches every other
user on any core-resolved host (the VM test users exclude it, like searxng). We
do **not** ship barebones pi: a full config is both seeded at install time and
made stow-ready for the operator.

## Decision

**Package.** Install the AUR prebuilt **`pi-coding-agent-bin`** (most-voted, deps
just glibc/gcc-libs, no build toolchain) via the [[AUR Helper]] as a `kind: user`
program. Pi's `grep`/`find` are ripgrep/fd-backed, so ensure `git`, `ripgrep`,
`fd` are present in core packages.

**Config delivery.** Pi's config tree lives under `~/.pi/agent/`. We ship it the
way every other config reaches a box: **seeded into `/etc/skel`** by the program
(the installer never stows, ADR 0095) **and** present at the repo root as a
stowable package (new top-level `.pi/` legacy stow tree) the operator stows by
hand. The installer does not stow it.

**Auth.** Provider is **Anthropic via Claude Pro/Max OAuth** (`pi`'s `/login`,
run once per machine) — no API key. Tokens land in `~/.pi/agent/auth.json`
(`0600`). That file holds secrets, so it is **gitignored and never stowed or
seeded** — credentials never enter the repo and are established per-machine.

**Skills.** Ship the full mattpocock/skills set, **vendored** (copied, not
symlinked) into `.agents/skills/` — the Vercel `skills` CLI's shared canonical
dir, which pi also reads (`~/.agents/skills/` globally, auto-discovered with no
settings entry). Vendoring keeps them present offline (in the repo clone) at
install time and stow-owned. The CLI writes a project-scope **`skills-lock.json`**
at the repo root, pinning each skill's upstream `source` + content hash; it is
committed as the reproducible pin (alongside the vendored tree itself). The
operator refreshes with `npx skills@latest add mattpocock/skills` run in-repo,
which overwrites in place and updates the lock.
Skills are not program-seeded — they ride the dotfiles clone and the operator's
stow, like every other stowed dotfile.

**Packages.** Pi's minimal core omits several Claude-Code staples; we add three
ready-made packages (the `abhinand5/pi-setup` ecosystem confirmed these exist as
packages, not hand-written extensions):
- **Web** — `nicobailon/pi-web-access`, pointed at the host's own SearXNG
  (`http://127.0.0.1:8080`, installed for every real user via User Core) with a
  keyless **DuckDuckGo fallback** so search still works if the searxng container
  is down — private-first, and it unblocks the `research` skill.
- **Todos** — `npm:@juicesharp/rpiv-todo` (Claude's TodoWrite analogue).
- **MCP** — `npm:pi-mcp-adapter`, which reads a Claude-Code-style `mcpServers`
  JSON (`command`/`args`/`env` for stdio, `url` for remote). We ship a starter at
  **`~/.pi/agent/mcp.json`** (inside the stowed `.pi/agent/` tree; pi's global
  override path). Secret values use `${VAR}` interpolation so no keys are
  committed; servers are lazy (connect only when a tool is called).

Sub-agents and plan mode stay out — pi omits them by design and the vendored
skills cover those workflows.

**Settings.** Curated global `~/.pi/agent/settings.json`: `defaultProvider:
anthropic`, `defaultModel` = **Opus 4.8** (pinned id at build),
`defaultThinkingLevel: high`, `enabledModels` cycling Opus/Sonnet/Haiku, `theme:
"noctalia"` (see ADR 0128), `quietStartup: true`, `enableSkillCommands: true`,
`defaultProjectTrust: ask`, and the three packages above in `packages`.

## Considered options

- **Build-from-source `pi` AUR package** (needs `nodejs>=22`) — rejected: the
  prebuilt `-bin` is more reproducible fleet-wide and pulls no build toolchain.
- **Declare `git:github.com/mattpocock/skills` in pi's `packages`** instead of
  vendoring — rejected: it fetches on first run (network), contradicting
  "shipped at install time" and the repo's offline-seed pattern (ADR 0109).
- **API-key auth** — rejected: OAuth reuses the existing Claude subscription and
  avoids a long-lived key on disk.
- **Scope pi to desktop/laptop only** (exclude from core's other hosts) —
  rejected for simplicity; pi on `minimal`/pure boxes is harmless, mirroring the
  obs-studio precedent.
- **Alias pi over `claude`** — rejected: both agents stay reachable by name.

## Consequences

- Pi lands on every host resolved over core (incl. `minimal`, pure-compositor),
  not only desktop/laptop. Accepted per ADR 0114.
- Auth is a manual per-machine `/login`; a fresh box has pi installed and
  configured but not logged in until the operator runs it.
- The operator owns skill refreshes (network, in-repo), same hands-on contract
  as stow itself.
- `defaultModel` is a pinned id that will drift as models are released; updating
  the default means bumping it.
