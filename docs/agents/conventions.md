# Repo conventions

Two layout rules for this repo.

## One `.claude/` — the repo root

There is exactly **one** `.claude/` directory: the repo root's, which holds the
project's Claude config. Claude Code otherwise drops per-directory state
(`.cc-writes`, `worktrees`, …) into a `.claude/` wherever it runs — those are
artifacts, not repo content. Delete any nested `.claude/` you find; `.gitignore`
already ignores every non-root `.claude/` so they never get committed.

**One exception**, and only one: `.installer/programs/dev/claude/home/.claude/`.
That is not a tooling artifact — it is the **dev/claude program's payload**, a
`home/` subtree that seeds the *target machine's* `~/.claude` (Config Apply /
`stow-configs.sh`, ADR 0134). It is force-tracked and must stay.

## Shell scripts end in `.sh`

Every shell script the repo's tooling **executes or sources as a file** carries
a `.sh` extension (e.g. `install.sh`, `stow-configs.sh`, `reorder-disks.sh`,
`serve-http.sh`). New internal scripts get `.sh`.

Exempt — where a bare name is required by convention or by a tool that resolves
the name itself:

- **Git hooks** — `.githooks/*` (git invokes them by exact name; an extension
  breaks the hook).
- **PATH executables** — commands installed onto a `PATH`: `.local/bin/*` and
  the seeded `/usr/local/bin/*` (e.g. `kde-seed-favorites`, `desktop-verify`).
  Unix commands don't carry a language extension, and they're referenced by bare
  name in `.desktop`/service files.
- **Shell config** — `*.zsh` topic files and `.zsh_aliases` (zsh's own
  extension; sourced dotfiles).
- **bats helpers** — `tests/lib/*.bash` loaded via bats `load` (which appends
  `.bash`, not `.sh`).
