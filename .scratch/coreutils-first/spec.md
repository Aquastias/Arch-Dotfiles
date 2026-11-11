# Spec: Coreutils first, Tool Reference as the allowlist

Status: ready-for-agent

Anchored by **ADR 0167** (supersedes the Tool Tiers of ADR 0153). Uses the
[[Tool Tiers]], [[Tool Reference]], [[Domain Tool]], [[Bash Feature Tier]],
[[Readability Rules]], [[Readability Lint]] glossary terms, plus
[[Installer Stdlib]], [[Shell Stdlib]], [[Guided Installer]].

## Problem Statement

The owner architected the installer and knows where most things live, but
many lines are unreadable to them without an LLM. If LLMs become too
expensive, they must still be able to change the code by hand. Two things
block them:

- They do not know what many commands, flags, jq features and bash idioms
  do (`jq` with `reduce`/`walk`/`def`, inline `awk`, `${!ref}`, `<<<`).
- Lines pack several steps together — long pipelines, long `&&`/`||`
  chains, jq/awk programs inline — so no single step can be followed.

ADR 0153 made the second problem worse: it banned simple coreutils
(`cut head tail wc tr uniq comm`) and pushed their work into dense `awk`
and `jq` programs. Today ~98k lines of shell across 696 files; jq on ~2083
lines, inline awk on ~454, 1.6k lines of `.awk` files.

## Solution

Code is written for a human who knows coreutils and looks the rest up in
one place. A new human doc, the [[Tool Reference]], lists every command,
flag, jq feature and bash feature the code may use, each with its meaning
and a real repo example. It is the allowlist: the [[Readability Lint]]
fails on anything it lacks, so it cannot drift. Coreutils and builtins come
first; jq, grep and sed are cut down to a small feature set; awk lives only
in commented files; long lines are split into named steps with a "what"
comment. The whole tracked codebase is refactored to these rules, with
behavior unchanged. Existing docs stay; the Tool Reference is the one doc
added.

## User Stories

1. As the owner, I want every command the code uses listed in one doc with
   its meaning, so that I can understand a line without an LLM.
2. As the owner, I want every flag the code uses listed with its meaning,
   so that an unknown flag never blocks me.
3. As the owner, I want each Tool Reference entry to show a real example
   from the repo, so that I see the command the way it is used here.
4. As the owner, I want the lint to fail on a command missing from the Tool
   Reference, so that the doc never falls behind the code.
5. As the owner, I want the lint to fail on a flag missing from the Tool
   Reference, so that new flags arrive explained.
6. As the owner, I want adding a Tool Reference entry to be the only way to
   allow a tool or flag, so that there is one place to look.
7. As the owner, I want coreutils (`cut head tail wc tr uniq comm`) allowed
   again for simple jobs, so that I read tools I already know instead of awk.
8. As the owner, I want obscure coreutils (`tsort ptx csplit numfmt pr`)
   kept out simply by having no entry, so that the allowed set stays small.
9. As the owner, I want `dirname`/`basename` called directly, so that I do
   not learn a wrapper on top of a tool I know.
10. As the owner, I want the `parent_directory`/`base_name` helpers deleted
    from every Commons world, so that only one way exists.
11. As the owner, I want `${path%/*}` kept only in the self-locating
    bootstrap line, so that the one place it is needed is explained once.
12. As the owner, I want jq kept as the one JSON tool, so that host
    profiles stay JSONC and frozen profile keys stay untouched.
13. As the owner, I want jq limited to path access, `//`, `select`, `map`,
    `keys`, `length`, `has`, so that each jq call is one readable step.
14. As the owner, I want jq flags limited to `-r -e -c -n --arg
    --argjson`, so that I learn a handful of flags only.
15. As the owner, I want `reduce`, `foreach`, `walk`, `def`, `paths`,
    `getpath`, `setpath`, `inputs` banned in jq, so that no jq program hides
    a loop.
16. As the owner, I want banned jq logic rewritten as a bash loop over
    simple jq output, so that the loop reads as bash.
17. As the owner, I want a commented `.jq` file allowed when bash truly
    cannot do the job, so that the rare complex case is isolated and
    explained.
18. As the owner, I want the "merge consecutive jq reads" rule removed, so
    that the code stops producing dense combined programs.
19. As the owner, I want grep limited to `-q -E -F -v -x -c -o -l`, so
    that grep calls stay recognisable.
20. As the owner, I want sed limited to `sed -i 's/a/b/'`, so that I never
    meet addresses, hold space or multi-command scripts.
21. As the owner, I want inline awk banned, so that no awk program hides
    inside a pipeline.
22. As the owner, I want awk allowed only in `.awk` files with a header
    comment and a comment on each rule, so that each awk program explains
    itself.
23. As the owner, I want system commands (`pacman zfs btrfs systemctl
    lsblk findmnt blkid mount sgdisk curl git ssh` …) allowed as Domain
    Tools, so that unavoidable tools are not fought.
24. As the owner, I want every Domain Tool flag the code uses listed in the
    Tool Reference, so that `pacman` and `zfs` flags are explained too.
25. As the owner, I want a Bash Feature Tier of allowed features (`[[ ]]`,
    `$( )`, arrays, `${#array[@]}`, `mapfile -t`, `while read -r … done <
    <(…)`, `${var:-default}`, here-docs, `local`, plain `(( ))`), so that
    I know which bash I need to read.
26. As the owner, I want `${!ref}`, `declare -n`, `eval`, `<<<`,
    `BASH_REMATCH`, `${var//a/b}`, `##`/`%%` pattern ops, `printf -v`,
    `${var@Q}` banned, so that no line relies on obscure bash.
27. As the owner, I want `<<<` replaced by `printf '%s\n' "$x" |`, so that
    input feeding uses one familiar shape.
28. As the owner, I want the Bash Feature Tier documented in the Tool
    Reference and checked by the lint, so that bash features follow the
    same allowlist as commands.
29. As the owner, I want at most 2 `|` per pipeline, so that I can follow a
    pipeline step by step.
30. As the owner, I want at most 2 `&&`/`||` per chain, so that control
    flow reads as `if` statements.
31. As the owner, I want any jq/awk/sed program over ~40 characters moved
    to a named variable or file, so that lines stay short.
32. As the owner, I want intermediate results in named variables, so that
    each step has a name telling me what it holds.
33. As the owner, I want a "what" comment above every jq/awk/sed program
    and every 2-pipe pipeline, so that I know what it produces before
    reading how.
34. As the owner, I want comments elsewhere to stay why-only, so that the
    code does not fill up with restatement.
35. As the owner, I want a denser form allowed only on a path the user
    waits on (guided TUI, install loops over packages/files/disks), so that
    speed is not lost where it matters.
36. As the owner, I want that exception to need a measured cost over 100 ms
    per action or over 2× total, so that "it's faster" is never a guess.
37. As the owner, I want such a line to carry `readability-ok: perf
    <before>→<after>` with the readable form commented above it, so that I
    still understand what it does.
38. As the owner, I want the lints themselves to follow every rule, so that
    I can debug the lint the day it wrongly blocks a commit.
39. As the owner, I want the rules to cover all tracked code (installer,
    tests, lints, `.local/bin`, `stow-configs.sh`, `.claude/` hooks), so
    that nowhere in the repo is unreadable.
40. As the owner, I want vendored skills, `.scratch/` and program `home/`
    payloads left out, so that third-party and app config files are not
    rewritten.
41. As the owner, I want the refactor to change no behavior, so that my
    installs keep working.
42. As the owner, I want each refactor ticket verified by the bats suite,
    and install-path tickets by a VM install, so that a regression is
    caught before it lands.
43. As the owner, I want frozen strings (host-profile keys, CLI flags,
    outside env vars, target paths, grepped strings) untouched, so that
    nothing outside the code breaks.
44. As the owner, I want readability rules docs and comment style docs
    amended to match ADR 0167, so that agent docs do not teach the old
    rules.
45. As an agent working in the repo, I want the lint to report violations
    as `rule: file:line: detail`, so that I can fix each one mechanically.
46. As an agent, I want `--list` to show every new-rule violation without
    failing, so that a refactor ticket can see its remaining work.
47. As the owner, I want the existing `readability-ok: <reason>` escape
    hatch kept for genuine exceptions, so that a rare need has a documented
    way out.
48. As the owner, I want the pre-commit gate to run the extended lint, so
    that no commit reintroduces dense code.

## Implementation Decisions

- **Tool Reference doc** — new human-facing Markdown doc under `docs/`.
  Sections: Coreutils, Builtins, Bash Feature Tier, jq, grep, sed, Domain
  Tools, bats. Each entry: name, one-line meaning, each used flag with a
  one-line meaning, one real repo example. A machine-readable shape the
  lint can parse (a fixed heading per tool, a fixed list form per flag),
  kept readable as prose.
- **Readability Lint** — the existing lint is extended, not replaced. Its
  report format, `--list`, `--fix-adr-links` and the `readability-ok`
  escape hatch stay. The old `tool` rule (replace-tier tools) and
  `sed-not-inplace` rule are retired; new rules:
  - `tool-reference`: a command at command position with no Tool
    Reference entry.
  - `flag-reference`: a flag of an allowed command with no entry.
  - `bash-feature`: a banned Bash Feature Tier construct.
  - `jq-feature`: a banned jq feature inside a jq program.
  - `inline-awk`: awk called with an inline program.
  - `sed-form`: sed other than `-i` with one `s///`.
  - `pipeline-length`: more than 2 `|` in one pipeline.
  - `chain-length`: more than 2 `&&`/`||` in one chain.
  - `program-length`: an inline jq/sed program over ~40 characters.
  - `what-comment`: a jq/awk/sed program or 2-pipe pipeline without a
    comment line directly above it.
  - `perf` exceptions: `readability-ok: perf` must carry a
    `<before>→<after>` measurement.
- **Lint file set** widened from installer-only to all tracked shell code,
  minus vendored skills, `.scratch/` and program payloads.
- **Lint internals** follow the rules: commented `.awk` files, readable
  bash driver; no exemption for lint code.
- **Commons path helpers** removed from the Installer Stdlib, chroot common
  and Shell Stdlib; callers use `dirname`/`basename`.
- **jq refactor** — banned features become bash loops over simple jq
  output; a commented `.jq` file only when bash cannot express it.
- **Readability rules doc and comment style doc** amended: Tool Tiers
  section replaced with a pointer to the Tool Reference and ADR 0167; the
  "merge jq reads" rule removed; the "what" comment rule added.
- **Frozen** set from ADR 0153 unchanged.
- **Delivery order** (full ticketed pass vs on-touch ratchet) still to be
  decided by the owner; tickets are cut after that choice.

## Testing Decisions

- A good test checks external behavior only: the lint's report lines and
  exit status for a given fixture, or an install's outcome — never which
  awk rule or helper produced it.
- **Seam 1 — Readability Lint CLI.** Each new rule gets fixture tests in
  the existing readability bats file: a temp repo with a violating file
  asserts the `rule: file:line` line; a clean variant asserts silence.
  Covers: unknown command, unknown flag, each banned bash and jq feature,
  inline awk, sed forms, pipeline and chain length, program length,
  missing "what" comment, `perf` reason format, widened file set,
  exclusions (vendored, `.scratch/`, payloads), strings/comments/heredocs
  ignored. Prior art: the 37 existing tests (replace-tier tools, sed
  without `-i`, pragma, ignores tool names in strings and heredocs).
- **Tool Reference parse** is tested through the same seam: a fixture
  reference with and without an entry flips a fixture's result.
- **"This repo passes the strict lint"** test stays as the whole-repo
  gate.
- **Seam 2 — behavior preservation.** Refactor tickets run the bats suite
  (`-j 4` max) and audit; install-path tickets close with a VM install,
  guided tickets with a guided-flow run, as ADR 0153 tickets did. No new
  seam.

## Out of Scope

- Changing the config format away from JSONC/jq.
- Renaming frozen strings (profile keys, CLI flags, outside env vars,
  target paths, grepped strings).
- Rewriting existing docs (ADRs, `CONTEXT.md` beyond glossary updates,
  agent docs beyond the rule amendments).
- Vendored `.agents/skills/`, `.scratch/`, program `home/` payloads.
- Behavior changes or bug fixes found en route — they get their own ticket.
- Choosing the delivery order; owner decides before tickets are cut.

## Further Notes

- Old dense forms survive in ADRs and `.scratch/` as history.
- More processes and lines mean slower code in places; accepted except
  under the measured `perf` exception.
- Host safety rules apply: one VM at a time, nothing heavy beside it.
