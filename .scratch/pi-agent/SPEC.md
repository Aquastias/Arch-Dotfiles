# Spec: Pi coding agent as a fleet-served, themed, skill-equipped agent

Status: ready-for-agent

Anchored by [[ADR 0127]] (pi fleet-wide, seeded + stow-ready) and [[ADR 0128]]
(pi follows Noctalia via user-template). Glossary: [[Pi Coding Agent]],
[[Pi Theme Template]].

## Problem Statement

The operator wants the **pi** coding agent available on their desktop and laptop
as a first-class, fully-configured tool — not the barebones upstream pi. Out of
the box pi has no curated settings, no skills, no web access, no todos/MCP, and
no theme that matches the rest of the desktop. Today only Claude Code is
provisioned; pi would have to be installed and hand-configured on every machine,
and its TUI would clash with the Catppuccin Mocha Sapphire look the
[[Wayland Shell Companion]] paints everywhere else.

## Solution

Ship pi fleet-wide through [[Host Core]] (the same path the obs-studio addition
took, per ADR 0114) with a **full, stow-ready config** that is also seeded at
install time. Pi comes pre-loaded with the full mattpocock skill set, a
privacy-first web tool, a todo tool, and an MCP adapter. Its TUI defaults to
**Catppuccin Mocha Sapphire** and, under the wlroots compositors, **follows live
Noctalia palette changes**; under KDE it stays fixed (matching the
[[App Theming Bridge]] isolation). Claude Code stays installed alongside; pi does
not replace it.

## User Stories

1. As a desktop/laptop user, I want pi installed automatically, so that I don't
   hand-install a coding agent on every machine.
2. As the operator, I want pi served via Host Core, so that desktop and laptop
   (which share all software) get it from one place.
3. As the operator, I want pi's full config present on a fresh install with no
   network, so that a freshly imaged box is usable offline.
4. As the operator, I want pi's config to also be stow-ready in the dotfiles
   repo, so that I can stow it by hand like my other dotfiles.
5. As the operator, I want the installer to seed but **never stow** pi's config,
   so that stow stays my manual, operator-owned action (ADR 0095).
6. As a user, I want pi to sign in to my existing Claude Max subscription, so
   that I don't manage a separate API key.
7. As a security-conscious operator, I want pi's auth tokens kept out of the
   repo, so that no secret is ever committed or stowed.
8. As a user, I want pi to default to Opus 4.8 at high thinking, so that my
   default agent is the most capable configuration.
9. As a user, I want to cycle to Sonnet/Haiku in-session, so that I can trade
   depth for speed without editing config.
10. As a user, I want the full mattpocock skill set available in pi, so that
    tdd/code-review/research/diagnosing/etc. work out of the box.
11. As the operator, I want the skills vendored (committed) in the repo, so that
    they are present offline at install time.
12. As the operator, I want `npx skills add mattpocock/skills` to refresh the
    vendored skills, so that I update them with one familiar command.
13. As a user, I want pi to find the skills automatically, so that no per-skill
    settings entry is needed.
14. As a user, I want web search/fetch in pi, so that the `research` skill and
    doc-grounded work function.
15. As a privacy-conscious user, I want web search to use my local SearXNG
    first, so that queries stay private.
16. As a user, I want web search to fall back to DuckDuckGo when SearXNG is down,
    so that search never hard-fails.
17. As a user, I want a todo tool in pi, so that I get Claude's TodoWrite-style
    task tracking.
18. As a user, I want an MCP adapter in pi, so that I can attach MCP servers in a
    Claude-Code-style config.
19. As the operator, I want a stow-ready starter MCP config, so that adding a
    server is editing one committed file.
20. As a security-conscious operator, I want MCP secret values referenced by
    env var, so that no key is committed.
21. As a user, I want pi's TUI themed Catppuccin Mocha Sapphire by default, so
    that it matches the rest of my desktop.
22. As a user on niri/Hyprland, I want pi's TUI to repaint when I change the
    Noctalia palette, so that the agent follows my live theme.
23. As a user on KDE, I want pi's TUI to stay Catppuccin Mocha Sapphire, so that
    it does not chase the Plasma/Breeze session (matching ADR 0104 isolation).
24. As a user, I want the live-follow to cover any Noctalia palette (10 builtins
    + community), so that I don't maintain per-palette theme files.
25. As a user, I want pi and Claude Code both reachable by their own names, so
    that neither shadows the other.
26. As the operator, I want the whole setup verifiable in a VM, so that I trust
    it before it reaches hardware.
27. As the operator, I want the static config verifiable in CI-style bats tests,
    so that regressions in packaging/stow/theme wiring are caught cheaply.

## Implementation Decisions

- **New Program `dev/pi`** (`kind: user`), installed by the [[Program Runner]]
  inside arch-chroot via the [[AUR Helper]]. Package: **`pi-coding-agent-bin`**
  (prebuilt; no build toolchain). Ensure **`git`**, **`ripgrep`**, **`fd`** are
  present in the [[Host Core]] package list (pi's grep/find are rg/fd-backed).
- **Placement in Host Core**, so desktop + laptop (and other core-resolved hosts)
  receive pi — the obs-studio precedent (ADR 0114). No per-profile packages
  block is added.
- **Dual config delivery.** Pi's `~/.pi/agent/` config is **seeded into
  `/etc/skel`** by the program and **also present as a stow-ready package** at the
  dotfiles repo root (a new top-level `.pi/` legacy [[Stow Tree]] entry). The
  installer seeds only; it never stows (ADR 0095) — the operator stows.
- **Auth.** Provider `anthropic` via Claude Max **OAuth** (pi's `/login`, once
  per machine). `~/.pi/agent/auth.json` (0600) holds tokens and is **gitignored,
  never stowed or seeded**.
- **Curated `settings.json`** (global): `defaultProvider: anthropic`,
  `defaultModel` = Opus 4.8 (id pinned at build), `defaultThinkingLevel: high`,
  `enabledModels` cycling Opus/Sonnet/Haiku, `theme: "noctalia"`,
  `quietStartup: true`, `enableSkillCommands: true`, `defaultProjectTrust: ask`,
  and the three packages below.
- **Packages** (pi's minimal core topped up; all confirmed to exist as packages):
  - Web: **`nicobailon/pi-web-access`**, pointed at `http://127.0.0.1:8080`
    (the host's SearXNG, installed for every real user via User Core) with a
    keyless **DuckDuckGo fallback**.
  - Todos: **`@juicesharp/rpiv-todo`**.
  - MCP: **`pi-mcp-adapter`** (reads a Claude-style `mcpServers` JSON). A starter
    is shipped at **`~/.pi/agent/mcp.json`** (pi's global-override path);
    secret values use `${VAR}` interpolation; servers are lazy.
- **Skills.** The full **mattpocock/skills** set is **vendored (copied, not
  symlinked)** into **`.agents/skills/`** at the repo root, with the Vercel CLI's
  **`.skill-lock.json`** committed as the pin. Stowed to `~/.agents/skills/`,
  which pi **auto-discovers** (no `skills` settings entry required). Refresh is
  **`npx skills@latest add mattpocock/skills`** run in-repo, which overwrites in
  place.
- **Theme follow via a Noctalia user-template** `[theme.templates.user.pi]`
  declared in the [[Wayland Shell Companion]]'s `config.toml`, rendering the live
  palette's Material roles into pi's 53 tokens at **`~/.pi/agent/themes/
  noctalia.json`**. Pi hot-reloads its active theme file, so **no `post_hook`**
  and **no change to the [[Live Theme Bridge]]** is needed. The single
  `noctalia.json` is **seeded with Catppuccin Mocha Sapphire** and live-rewritten
  **only in compositor sessions**; KDE never runs the template, so it stays
  Catppuccin Mocha Sapphire there.
- **Token map** (from the approved prototype; key assignments, not a full theme):
  `accent / borderAccent / toolTitle / mdLink / syntaxKeyword =
  colors.primary (#74c7ec)`; `text = on_surface (#cdd6f4)`;
  `muted = on_surface_variant`; `dim / outline = outline (#6c7086)`;
  `background/surface = surface (#1e1e2e)`; `selectedBg = surface_container`;
  `success = green`, `error = red (#f38ba8)`, `warning = yellow`;
  `thinkingHigh border = red`; `toolDiffAdded = green`,
  `toolDiffRemoved = red`; `bashMode = peach`; terminal tokens from the palette's
  `terminal_*` roles. Template placeholders are Mustache
  `{{colors.<role>.default.hex}}` (`.hex_stripped` where a `#` must be dropped).

## Testing Decisions

Good tests assert **external behavior**, not internals: the resolved
configuration, the materialized stow tree, the presence/shape of shipped files,
and live TUI behavior — never private shell functions.

- **Static seam — new `pi-agent.bats`** (under `.installer/tests/config/`,
  modeled on **`noctalia-stow.bats`**). Asserts, without a real install: the
  `dev/pi` program config validates and is wired into the resolved profile;
  `pi-coding-agent-bin` + `git`/`ripgrep`/`fd` resolve into desktop + laptop;
  the stow tree carries `settings.json` (with the pinned keys), the seeded
  `noctalia.json` whose accent is `#74c7ec`, and the starter `mcp.json`;
  `.agents/skills/` + `.skill-lock.json` exist; `.gitignore` excludes
  `auth.json`; and `config.toml` declares `[theme.templates.user.pi]`.
  Prior art: `noctalia-stow.bats`, `niri/kde/hyprland-adapter.bats`,
  `profiles-aur.bats`, `packages.bats`.
- **Behavioral seam — VM via `vm-agent.sh`** on the `arch-combined`
  [[Agent-Controllable VM]] (reuses existing harness, no new infra): `pi` is on
  PATH; the vendored skills and the web/todo/mcp packages load; `session niri`
  then a Noctalia palette change **repaints** the pi TUI (live-follow);
  `session kde` leaves the pi TUI on Catppuccin Mocha Sapphire (no-follow).
  Prior art: `flow-persistent.bats`, `vm-agent.bats`, `vm-cli.bats`.

## Out of Scope

- Aliasing `pi` over `claude` or otherwise replacing Claude Code.
- Sub-agents, plan mode, and NotebookEdit (pi omits the first two by design;
  the vendored skills cover those workflows).
- Hand-generated static pi theme JSONs per Noctalia palette (live-follow covers
  them).
- Shipping actual MCP servers — only a starter/example `mcp.json` is provided;
  concrete servers (and their secrets) are operator-added.
- Automating `/login` — auth is a deliberate per-machine manual step.
- Theming pi under bare/other WMs beyond "compositor follows, KDE static".
- Excluding pi from `minimal`/pure hosts (accepted to land fleet-wide).

## Further Notes

- `defaultModel` is a pinned id that will drift as models ship; bumping the
  default means editing `settings.json`.
- Skill refresh is operator-run and needs network (same hands-on contract as
  stow itself); the in-place overwrite is the documented behavior of re-running
  the Vercel `skills` CLI `add`.
- `pi-mcp-adapter` also reads `~/.config/mcp/mcp.json`, `.pi/mcp.json`,
  `.mcp.json`, and `~/.agents/mcp.json`; we standardize on `~/.pi/agent/mcp.json`
  inside the stowed tree but those paths remain available to the operator.
- The web and MCP packages share an author (nicobailon), a coherent pairing.
- The default palette now lives in one more place (the seeded `noctalia.json`);
  a default-palette change must update it alongside the ADR 0109 seed points.
- A prototype of the themed TUI (four palettes, simulating live-follow) lives at
  `.scratch/pi-tui-theme-prototype.html` as a throwaway primary source.
