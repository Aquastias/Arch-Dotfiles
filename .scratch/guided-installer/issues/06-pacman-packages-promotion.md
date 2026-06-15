# Host breadth II — Pacman + Packages + program promotion

Status: ready-for-agent

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

Add the **Pacman**, **Packages**, and **Host ▸ Advanced** content.

Pacman: `options.mirror_countries` (fzf-multi, default
Germany/Switzerland/Sweden/France/Romania) feeding `reflector --country`
in `install_base`, plus an `options.multilib` toggle (default `true`)
that makes the currently-unconditional `enable_multilib` honour the flag.

Packages: `packages.extra` typed inline, with **program promotion** — a
typed name that resolves to a `programs/<category>/<name>/` is promoted
to `system_programs` (installed via the Program Runner); non-matches stay
repo packages; a name that is both resolves as the program. Resolution is
TUI-side; the back-end contract is unchanged.

Host ▸ Advanced: `system_programs` (fzf-multi over `programs/*/*/`),
`sysctl` (swappiness pre-set to 10 from Host Core + add/override any
`key=value`), Persist Extensions, `post_install` toggles, `dotfiles_repo`.

## Acceptance criteria

- [ ] `options.mirror_countries` (default 5) is emitted and drives
      `reflector --country`; offline, the picker falls back to the
      default list plus free-text.
- [ ] `options.multilib` (default true) gates `enable_multilib`.
- [ ] A typed `packages.extra` name matching a program is promoted to
      `system_programs`; a non-match stays a package; an ambiguous name
      resolves as the program.
- [ ] Host ▸ Advanced edits `system_programs`, `sysctl` (swappiness 10
      default), Persist Extensions, `post_install`, `dotfiles_repo`.
- [ ] bats: emitter promotion split + the new accessors.

## Blocked by

- `01-guided-install-tracer-bullet`
