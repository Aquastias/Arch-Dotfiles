# ADR 0032: `lib/` folder taxonomy and the ≥2-file rule

## Status
Accepted

## Context
`.os/lib/` grew to ~40 sibling files. Domain relationships were encoded
only in filename prefixes (`layout-*`, `zfs-*`, `wipe-*`, `config*`), so
understanding one concept — the Config cluster, the Layout Module, the
Disk Wipe — meant scanning the whole directory and reading prefixes.
There was no locality by domain and no structural signal about which
files change together, which hurts both maintainers and AFK agents
navigating the tree.

This ADR records the organising decision for the lib-taxonomy-refactor
(PRD: `.scratch/lib-taxonomy-refactor`). The first slice folders the
Config cluster; later slices fold `zfs/`, `layout/`, `wipe/`,
`packages/`, `profiles/` the same way.

## Decision
Group `lib/` files into **domain folders**, governed by one rule:

- **A folder exists only when ≥2 related files justify it.** A lone
  module stays a file at the `lib/` root rather than a one-file folder.

Root singletons (kept flat): `common.sh`, `globals.sh`, `jsonc.sh`
(primitives); `install-state.sh`, `finalize.sh` (singletons);
`grub-common.sh`, `live-medium.sh` (shared cross-domain);
`secrets.sh`, `impermanence-common.sh` (domain singletons); `picker.sh`.
`lib/shell/` and `lib/chroot/` are pre-existing folders, left as-is.

Two corollaries make the moves behavior-preserving:

- **Public function names stay stable.** Only file paths change; a move
  is never a rename of an identifier. `grep` for a function still finds
  it, and call sites change only their `source` line.
- **Intra-`lib/` sibling sources are repointed by depth, not removed.** A
  module that sources a root singleton via `${BASH_SOURCE[0]%/*}/X.sh`
  becomes `${BASH_SOURCE[0]%/*}/../X.sh` once it lives one level deeper;
  a module that sources a true sibling in the same folder keeps the
  same-dir form.

The chroot keeps its **flat** `/root/lib/` copy layout: files copied
into the new root by `configure_system` (and the `kde.sh` adapter that
sources them) move in lockstep with the repo path, but the copy
destination tracks the repo subfolder (e.g.
`/root/lib/config/categorized-list.sh`) so the one relative `source`
path resolves in both the chroot and the test context.

Tests mirror the `lib/` folder structure (`tests/config/` for
`lib/config/`), and `tests/run.sh` discovers `*.bats` recursively while
excluding the vendored bats-core checkout.

## Considered alternatives
- **Keep the flat directory, rely on filename prefixes.** The status
  quo; no locality, no folder to open, prefixes drift. Rejected.
- **One folder per module regardless of size.** Produces one-file
  folders that add nesting without locality. Rejected in favour of the
  ≥2-file rule.
- **Rename functions to match new module names.** Maximally "clean" but
  turns a mechanical, behavior-preserving move into an N-site identifier
  churn with no test-surface benefit. Rejected; function names are
  stable.

## Consequences
- Each domain has a folder to open; files that change together live
  together. The tree gives an AFK agent a structural map.
- Historical ADRs (0012–0031) are **not** rewritten — they reference the
  pre-refactor paths and stand as the record of what was true when
  decided. New decisions get new ADRs from 0032 on.
- A behavior-preserving move is verified by the existing bats suite
  passing unchanged plus the static `audit.sh` manifest; the suite is
  the regression net, not new tests.
- `audit.sh`'s host-side lib manifest now lists full relative paths so
  it tolerates subfolders.
