# ADR 0167: Coreutils first, Tool Reference as the allowlist

## Status
Accepted — not yet implemented. Supersedes the Tool Tiers of [ADR 0153];
its names, sizes, prefixes and ADR-link rules stay.
Amended 2026-11-12: grep also allows `-w` (whole words): its regex spelling
reads worse than the flag.

## Context
The owner architected the installer but cannot read many of its lines
without an LLM. If LLMs become too expensive, the code must still be
changeable by hand. Two things block reading, not the tool count itself:
not knowing what a command or flag does, and lines so long that no one
step can be followed. [ADR 0153] made it worse in one place: it sent
`cut tr head tail wc` work to `awk` and `jq` programs, packing several
steps into one dense line. The repo today: ~98k lines of shell in 696
files, `jq` on ~2083 lines (`def`, `reduce`, `walk`, `getpath` included),
`awk` on ~454, plus 1.6k lines of `.awk` files.

## Decision
Code is written for a human who knows coreutils and looks up the rest.
Scope: all tracked code — `.installer/` (tests and lints included),
`.local/bin`, `stow-configs.sh`, `.claude/` hooks. Out: vendored
`.agents/skills/`, `.scratch/`, program `home/` payloads.

1. **[[Tool Reference]] is the allowlist.** `docs/tool-reference.md`
   lists every command, every flag used, every allowed jq and bash feature,
   each with a one-line meaning and a real repo example. The lint fails on
   a command or flag the doc lacks, so the doc cannot drift. Adding an
   entry is how a tool or flag becomes allowed.
2. **Tool order.**
   - **Coreutils + bash builtins first.** Any coreutil may be used once it
     has an entry; `cut head tail wc tr uniq comm` return for simple jobs.
     `dirname`/`basename` replace the `parent_directory`/`base_name`
     helpers, which are deleted; `${path%/*}` survives only in the
     self-locating bootstrap line.
   - **jq** stays the one JSON tool (host profiles are JSONC). Allowed:
     path access, `//`, `select`, `map`, `keys`, `length`, `has`, flags
     `-r -e -c -n --arg --argjson`. Banned: `reduce`, `foreach`, `walk`,
     `def`, `paths`, `getpath`/`setpath`, `inputs`. Banned logic becomes a
     bash loop over simple jq output, or a commented `.jq` file when bash
     cannot do it. The "merge consecutive jq reads" rule is dropped.
   - **grep** with `-q -E -F -v -x -c -o -l -w` only.
   - **sed** only as `sed -i 's/a/b/'`: no addresses, holds or
     multi-command scripts.
   - **awk** never inline; only in `.awk` files with a header comment and
     a comment on each rule.
   - **[[Domain Tool]]s** (`pacman zfs btrfs systemctl lsblk findmnt
     blkid mount sgdisk curl git ssh` …) are allowed; their used flags are
     listed in the Tool Reference like any other.
3. **[[Bash Feature Tier]].** Allowed: `[[ ]]`, `$( )`, arrays,
   `${#array[@]}`, `mapfile -t`, `while read -r … done < <(…)`,
   `${var:-default}`, here-docs, `local`, plain `(( ))`. Banned: `${!ref}`,
   `declare -n`, `eval`, `<<<`, `BASH_REMATCH`, `${var//a/b}` and
   `##`/`%%` pattern ops (bootstrap line aside), `printf -v`, `${var@Q}`.
   `<<<` becomes `printf '%s\n' "$x" |`.
4. **One step per line.** At most 2 `|` per pipeline and 2 `&&`/`||` per
   chain. A jq/awk/sed program over ~40 characters moves to a named
   variable or file. Intermediate results get named variables.
5. **"What" comments.** Above every jq/awk/sed program and every 2-pipe
   pipeline, a comment says what it produces. Elsewhere comments stay
   why-only ([comment-style.md](../agents/comment-style.md)).
6. **Speed.** Readability wins unless the path is one the user waits on
   (guided TUI, an install step looping over packages/files/disks) *and*
   the readable form measurably costs >100 ms per action or >2× total.
   Then the dense form carries `readability-ok: perf <before>→<after>`
   with the readable form in a comment above it.
7. **Lints obey the rules.** `readability-scan.awk` and friends are code
   the owner debugs when a commit is wrongly blocked; no exemption.

Existing docs stay as they are; the Tool Reference is the one human doc
added. `readability.md`, `comment-style.md` and `CONTEXT.md` are amended
to match.

## Considered Options
- **Keep [ADR 0153] Tool Tiers** (few binaries, awk/jq for everything) —
  rejected: fewer tools, but each line holds a program the owner cannot
  read.
- **Drop jq for a bash-native config format** — rejected: rewrites every
  host profile and breaks frozen profile keys.
- **Allowlist commands only, not flags** — rejected: an unknown flag is
  as opaque as an unknown command.
- **Readability always beats speed** — rejected: the guided TUI redraws
  on every key; a measured exception is kept, behind a reason.

## Consequences
- More processes, more lines, slower in places; accepted except where
  item 6 applies.
- The lint grows a command/flag parser checked against the Tool
  Reference; it must stay readable itself (item 7).
- Delivery order (full pass vs on-touch ratchet) is decided separately.
- Old dense forms survive in ADRs and `.scratch/` as history.

<!-- ADR links: generated by readability.sh --fix-adr-links -->
[ADR 0153]: 0153-human-readable-installer-code.md
