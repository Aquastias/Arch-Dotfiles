# 01: Install pi fleet-wide with base config

**What to build:** On a fresh desktop/laptop install, the `pi` coding agent is
present and launchable with a curated base config, and `pi`'s `/login` signs in
to the operator's Claude Max subscription. The config is seeded at install time
(offline) and is also stow-ready in the dotfiles repo for the operator to stow by
hand. No secret ever enters the repo.

Scope: a new `dev/pi` Program (`kind: user`) installs `pi-coding-agent-bin` via
the AUR Helper; `git`/`ripgrep`/`fd` are ensured in the Host Core package list
(pi's grep/find are rg/fd-backed). A minimal `~/.pi/agent/settings.json`
(`defaultProvider: anthropic`, `defaultModel` = Opus 4.8 pinned at build,
`defaultThinkingLevel: high`, `enabledModels` cycling Opus/Sonnet/Haiku,
`quietStartup: true`, `defaultProjectTrust: ask`) is both seeded into `/etc/skel`
and present at the repo-root `.pi/` stow tree. `auth.json` is gitignored and
never seeded or stowed. The installer seeds only — it never stows (ADR 0095).
Pi is served via Host Core so desktop + laptop both receive it (ADR 0114). This
ticket establishes the `.pi/` stow package + `/etc/skel` seeding that later
tickets extend. Anchored by ADR 0127.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] `dev/pi` program config validates and resolves into the desktop and laptop
      profiles.
- [ ] `pi-coding-agent-bin` plus `git`/`ripgrep`/`fd` resolve into the Host Core
      package set.
- [ ] `settings.json` with the pinned keys is seeded into `/etc/skel` and present
      in the repo-root `.pi/` stow tree.
- [ ] `.gitignore` excludes `~/.pi/agent/auth.json`; it is never seeded or stowed.
- [ ] The installer does not stow the config (seed-only).
- [ ] New `pi-agent.bats` (modeled on `noctalia-stow.bats`) asserts the above
      static facts.
- [ ] On the `arch-combined` VM, `pi` is on PATH and launches.
