# ADR 0153: Human-readable installer code

## Status
Accepted — design only; not yet implemented.

## Context
`.installer/` grew to ~43k lines of bash across 283 files. Names are
abbreviated (`_ctl_pw_missing`, `fa_`, `blcommon_`, `cfgstate_`), prefixes
are inconsistent or missing (`ensure_`, `write_`), locals are one letter
(`f`, `d`, `v`), files run to 4k lines, and ~25 external tools overlap
(`cut | tr | head` beside `awk`). The owner, returning after months, can't
read the flow or guess where a function lives. Docs mention ADRs ~350 times;
one is a link.

## Decision
A pure-refactor pass over `.installer/` (lib, vm, tools, tests) plus rules
every future change — human or agent — must follow
(`docs/agents/readability.md`, pointed to from `CLAUDE.md`):

- **Flow first.** Each entry script opens with a `main()` that reads as a
  table of contents. Lib file headers carry `Used by:`.
  `ARCHITECTURE.md` links to those `main()`s instead of restating them.
- **No abbreviations.** Allowlist only domain acronyms (`zfs esp gpu aur iso
  vm ssh uid luks tty`); short locals only `i`/`j` (counters), `rc`.
- **File-stem prefixes.** A function's prefix names its file
  (`config/history.sh` → `history_`); a directory forming one public API
  uses the dir name for public functions (`feature_audit_`), file stem for
  private (`_controller_`). Leading `_` = file-private. Exception:
  **Interface Functions** take their glossary role name
  (`root_adapter_mkfs`, `data_formatter_mkfs`). The full old→new **Prefix
  Map** is approved once, then applied.
- **Name shape.** Actions `<prefix>_<verb>_<object>`; predicates
  `is_/has_/can_` (status, no output); producers named for what they print.
- **Globals** `UPPER_SNAKE` (shared) / `_MODULE_UPPER` (private), declared
  at file top with a one-line meaning.
- **Size caps.** Functions ≤ ~50 lines, ≤ 3 nesting levels (split when
  touched); files ≤ 500 lines.
- **Tool Tiers.** One tool per job: `jq` JSON, `awk` text, `grep` filter,
  plus `sort` and file ops. `sed` only for `-i`. Replace `cut tr head tail
  wc paste comm uniq column bc xargs realpath readlink`; wrap
  `basename`/`dirname` in a Commons path helper. Merge repeated `jq` calls
  when the merged filter stays short. Never trade readability for one fewer
  binary.
- **Linked ADRs.** Every `ADR NNNN` in tracked `.md` (except
  `.scratch/` and vendored `.agents/skills/`; ADR-to-ADR mentions included) is
  a link — Markdown shortcut reference `[ADR NNNN]` plus a generated
  definition block, so lines keep their width. Code comments
  keep plain `(ADR NNNN)`.
- **Readability Lint** (`tests/readability.sh` + bats) enforces the above
  as a ratchet: a **Readability Baseline** lists today's violations; new
  ones fail, the baseline only shrinks.

Frozen (not renamed): host-profile config keys, CLI flags, externally read
env vars, paths installed on the target, and strings tests/audits grep for.
`CONTEXT.md` terms are renamed first when a code rename touches one; ADRs
are never edited for renames. Bugs found en route get their own ticket.

## Considered Options
- **Short module tags** (`fa_`, `ctl_`) — rejected: unreadable without the
  map, the thing this pass removes.
- **Directory prefixes** (`config_` for all of `config/`) — rejected: still
  need grep to find the file; stem prefix names it.
- **Raw parameter expansion** over `dirname`/`basename` — rejected:
  `${p%/*}` is fewer tools but less readable; a named helper is both.
- **Docs-only rules, no lint** — rejected: agents drift. **Lint without a
  baseline** — rejected: red from day one.

## Consequences
- Delivered as tickets: foundations (this ADR, doc, lint, Prefix Map) →
  ADR links → pilot `03-install.sh` + direct libs, style review → the rest
  in lifecycle order, `guided/controller.sh` last. Separate rename / tools /
  split commits per ticket.
- Each commit: shellcheck, bats, `audit.sh`, Readability Lint green. A VM
  install closes each install-path ticket; guided tickets a guided-flow run.
- Old names survive in ADRs and `.scratch/` as historical record.
