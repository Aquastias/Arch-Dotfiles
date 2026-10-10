# Readability

How installer (`.installer/`) code is named, sized, and structured so its owner
can read it after months away (ADR 0153). Every change — human or agent —
follows these rules. The Readability Lint enforces the mechanical ones; the
rest are on you. Comments follow [comment-style.md](comment-style.md).

## Flow first

- Each entry script opens with a `main()` near the top that calls phase
  functions only — it reads as the script's table of contents.
- Each lib file header carries a `Used by:` line naming the scripts/libs that
  source it.
- `ARCHITECTURE.md` links to the `main()`s instead of restating the flow.

## Names

- **No abbreviations.** Spell words out: `password` not `pw`, `encryption` not
  `enc`, `config` not `cfg`, `directory` not `dir`, `navigation` not `nav`.
  Allowed short tokens: domain acronyms (`zfs esp gpu aur iso vm ssh uid luks
  tty`, plus standard ones like `os id ip json url uuid`), command names used
  as words (`jq mv cp rm ln`), and small English words.
- **Locals** name their content (`dataset`, `profile_path`). Only `i`/`j`
  (numeric loop counters) and `rc` (exit status) may be short.
- **Prefix.** A function's Prefix names the file that defines it
  (`config/history.sh` → `history_`). A directory exposing one public API lends
  its name to public functions (`feature_audit_`); private ones use
  `_<file stem>_`. A leading `_` means file-private. The full Prefix Map is
  below.
- **Name shape.**
  - Actions: `<prefix>_<verb>_<object>` — `pools_create_root`.
  - Predicates: `<prefix>_is_/has_/can_…` — return a status, print nothing.
  - Producers (print a value): named for what they print —
    `guided_effective_value`.
- **Interface Functions** — one name implemented once per backend, the sourced
  module answering — take their glossary role name, not a file Prefix:
  `root_adapter_*` (Root Layout Adapter), `data_formatter_*` (Data Group
  Formatter).
- **Globals** are declared together at the top of their file with a one-line
  meaning: `UPPER_SNAKE` when shared, `_MODULE_UPPER` when file-private.

## Size

- Files ≤ 500 lines — split by responsibility; each new file gets its own
  Prefix.
- Functions ≤ ~50 lines and ≤ 3 levels of `if`/`for`/`while`/`case`
  nesting — split when you touch one that exceeds it.

## Tool Tiers

One tool per job. Never trade readability for one fewer binary.

- **Core:** bash builtins, `jq` (all JSON), `awk` (any multi-field or
  multi-step text work), `grep` (filtering), `sort`, file ops (`mkdir cp mv rm
  ln find mktemp`).
- **`sed`:** in-place edits (`sed -i`) only; other transforms go to `awk`.
- **Replace:** `cut tr head tail wc paste comm uniq column bc xargs realpath
  readlink` → a core tool or builtin (`mapfile`, `${#array[@]}`, `printf`).
  `basename`/`dirname` → `parent_directory` / `base_name`, defined in every
  Commons world (Installer Stdlib, chroot common, Shell Stdlib). Before any
  stdlib is sourced — a script locating its own directory — use the existing
  idiom `"${BASH_SOURCE[0]%/*}"`.
- Merge consecutive `jq` reads of one input into one program when the result
  stays short or is factored with named `def`s.

## Frozen

Never renamed by readability work: host-profile JSON keys, CLI flags, env vars
read from outside `.installer/`, paths written on the target, and any string a
test, audit, or Known Noise pattern greps for. Renames touching a domain term
update `CONTEXT.md` first; ADRs are never edited for renames.

## Readability Lint

`.installer/tests/readability.sh` (scanner: `readability-scan.awk`; run by
`readability.bats` in the suite) reports `rule: file:line: detail` for:

| Rule | Catches |
| --- | --- |
| `function-name` | abbreviated token in a function name |
| `local-name` | abbreviated / single-letter `local`, `declare`, or `for` var |
| `function-length` | function over 50 lines |
| `nesting` | keyword nesting deeper than 3 |
| `file-length` | file over 500 lines |
| `tool` | a replace-tier tool at command position |
| `sed-not-inplace` | `sed` without `-i` |

The allow/deny token lists live in the scanner's `BEGIN` block — extend them
there. Only code is scanned: quoted text, comments, and heredoc bodies are
skipped, as are program `home/` payloads.

**Ratchet.** `readability-baseline.txt` lists the violations that existed when
the lint landed, keyed `rule<TAB>file<TAB>symbol` (no line numbers). A
violation not in it fails; an entry no longer violated fails as stale. So:

- New code must be clean. Do not add baseline entries by hand.
- When you fix a violation, delete its baseline line (the stale check tells
  you which). `readability.sh --write-baseline` regenerates it — review the
  diff: it must only shrink.
- `readability.sh --list` prints every violation, ignoring the baseline.

**Escape hatch.** A line containing `readability-ok: <reason>` is exempt; on a
function's opening line it exempts the whole function. Use it for genuine
exceptions (a `head` that cuts a stream on purpose), never to dodge a rename.

## Prefix Map

Pending approval (ticket 02 of `.scratch/human-readable-installer/`).
