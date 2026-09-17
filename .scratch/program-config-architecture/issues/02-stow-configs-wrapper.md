Status: done

# `./stow-configs` wrapper

## Parent

`.scratch/program-config-architecture/PRD.md` (ADR 0134).

## What to build

An operator-facing, repo-root `./stow-configs` command that applies per-Program
config by hand from the single `home/` source — the day-2 twin of the Runner's
install-time pass. Bare run applies every Program that ships a `home/`;
`--except <prog…>` subtracts; positional `<prog…>` selects exactly that subset.
Uses `stow --adopt --no-folding` so it works whether `$HOME` is empty (fresh
clone) or already installer-seeded (same bytes, single source).

The selection logic (which Programs, honoring `--except`/args) is a pure
module split from the `stow` side effect so it is unit-testable.

## Acceptance criteria

- [ ] Discovery/filter is a pure module: `(programs root, --except / positional
      args) → ordered list of Programs to stow`.
- [ ] Bare run lists all Programs with a `home/`; `--except` subtracts;
      positional args select exactly the named subset; a Program without a
      `home/` never appears.
- [ ] The wrapper stows each selected Program's `home/` into `$HOME` with
      `--adopt --no-folding`; safe on empty and seeded `$HOME`.
- [ ] Discovery/filter unit tests (bats): default-all, `--except`, subset, and
      no-`home/` cases.

## Blocked by

- `01-tracer-decouple-config-apply-kitty.md` (establishes the `home/`
  convention and a migrated example).
