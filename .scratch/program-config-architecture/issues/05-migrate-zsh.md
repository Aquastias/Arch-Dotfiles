Status: ready-for-agent

# Migrate `zsh` to `home/`-only, decoupled

## Parent

`.scratch/program-config-architecture/PRD.md` (ADR 0134).

## What to build

Migrate the gnarly Program: `zsh`. Its config becomes single-source under
`home/` (repo-root `.zsh/`, `.zshrc`, `.p10k.zsh`, `.zshenv`, `.zsh_aliases`
deleted). `install.sh` stops seeding the user's `$HOME` config; it keeps a
build-time read of its own `home/` into a **throwaway `ZDOTDIR`** purely to
pre-warm the zinit plugin cache. `/etc/skel` and `/root` are seeded by the
config-apply pass from the same `home/` source, not by `install.sh`.

## Acceptance criteria

- [ ] `zsh` config lives only under its `home/`; all repo-root zsh files
      removed; the drift test's target no longer has a second author.
- [ ] `install.sh` does not seed `$HOME` config; it warms the zinit cache via a
      throwaway `ZDOTDIR` reading its own `home/`.
- [ ] `/etc/skel` and `/root` receive the zsh config from the apply pass, from
      the single `home/` source.
- [ ] `config_exclude: ["zsh"]` installs the tooling but applies no user config.
- [ ] VM harness confirms a fresh user lands on a working, themed zsh with a
      warmed cache (no first-login plugin clone).

## Blocked by

- `01-tracer-decouple-config-apply-kitty.md` (the apply pass + `/etc/skel` +
  `/root` seeding must exist).
