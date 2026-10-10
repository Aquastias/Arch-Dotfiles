# Spec: Human-readable installer code

Status: ready-for-agent

Anchored by **ADR 0153**. Uses the [[Readability Rules]], [[Prefix]],
[[Prefix Map]], [[Interface Function]], [[Tool Tiers]], [[Readability Lint]]
glossary terms, plus [[Installer Stdlib]], [[Shell Stdlib]],
[[Root Layout Adapter]], [[Data Group Formatter]], [[Feature Audit]],
[[Guided Installer]].

## Problem Statement

The installer has grown to ~43k lines of bash over 283 files and 150+ ADRs of
features. Its owner can no longer read it after time away:

- names are abbreviated tags (`_ctl_pw_missing`, `fa_`, `blcommon_`,
  `cfgstate_`, `_noc_`, `_lm_`) that mean nothing without a mental map;
- some files have no Prefix at all (`ensure_`, `write_`, `enable_`), and
  two files in one directory use unrelated tags;
- locals are one letter (`f`, `d`, `p`, `v`, `s`, `n`) or abbreviations
  (`cfg`, `enc`, `nav`, `fs`);
- the guided controller alone is 4k lines / 157 functions, and 12 more lib
  files exceed 500 lines;
- the flow — which script runs what, in what order — can't be read from the
  code; the architecture diagrams exist but drift from it;
- ~25 external tools overlap (`cut | tr | head` chains beside `awk`; runs of
  `jq` calls on one file);
- docs mention ADRs ~350 times, only one is a clickable link.

Agents keep adding code in the same style, so the problem grows.

## Solution

A behaviour-preserving refactor of the installer to the Readability Rules,
delivered in reviewable tickets, plus guardrails so every future change —
human or agent — stays readable:

- every entry script opens with a `main()` that reads as the install's table
  of contents; every lib file says who uses it;
- every function name says which file it lives in (its Prefix) and whether it
  acts, tests, or prints; every variable is a real word;
- big files and functions are split along responsibilities;
- one tool per job per the Tool Tiers;
- every ADR mention in the docs is a link;
- a Readability Lint, ratcheted against a Readability Baseline, fails any
  new violation, and an agent doc + `CLAUDE.md` pointer teaches the rules.

## User Stories

1. As the repo owner returning after months, I want each entry script to open
   with a `main()` listing its phases in order, so that I see the whole flow
   before reading any detail.
2. As the repo owner, I want every lib file header to say which scripts use
   it, so that I know where it sits in the flow without grepping.
3. As the repo owner, I want `ARCHITECTURE.md` to link to the `main()`s
   instead of restating them, so that the doc can't drift from the code.
4. As the repo owner, I want a function's Prefix to name the file that
   defines it, so that I open the right file from the name alone.
5. As the repo owner, I want a directory exposing one public API (Feature
   Audit, Guided Installer) to lend its name to its public functions, so that
   callers see the module, not an internal file.
6. As the repo owner, I want file-private functions marked with a leading
   `_`, so that I know what is safe to change without checking callers.
7. As the repo owner, I want actions named `<prefix>_<verb>_<object>`, so
   that I read what a call does.
8. As the repo owner, I want predicates named `is_/has_/can_` that only
   return a status, so that I read `if` conditions as sentences.
9. As the repo owner, I want producers named after what they print, so that
   `$(…)` captures say what they hold.
10. As the repo owner, I want no abbreviations except domain acronyms (`zfs
    esp gpu aur iso vm ssh uid luks tty`), so that I never decode `pw`, `enc`,
    `ctl`, `nav`, `fa`, `cfg`.
11. As the repo owner, I want locals named for their content (`dataset`,
    `profile_path`), with only `i`/`j` counters and `rc` short, so that a
    function body reads without tracking letters.
12. As the repo owner, I want each file's globals declared together at its
    top with a one-line meaning, so that I know a file's state at a glance.
13. As the repo owner, I want shared globals `UPPER_SNAKE` and private ones
    `_MODULE_UPPER`, so that scope shows in the name.
14. As the repo owner, I want Interface Functions named after their glossary
    role (`root_adapter_mkfs`, `data_formatter_mkfs`), so that the
    per-filesystem contract matches `CONTEXT.md`.
15. As the repo owner, I want to approve one full old→new Prefix Map up
    front, so that name debates happen once, not per ticket.
16. As the repo owner, I want files capped at 500 lines, so that each file
    holds one responsibility I can keep in my head.
17. As the repo owner, I want the guided controller split into responsibility
    files, so that its 157 functions are no longer one 4k-line scroll.
18. As the repo owner, I want functions over ~50 lines or nested deeper than
    3 levels split when touched, so that each reads top to bottom.
19. As the repo owner, I want JSON handled by `jq`, text by `awk`, filtering
    by `grep`, so that I learn one tool per job.
20. As the repo owner, I want `cut`, `tr`, `head`, `tail`, `wc`, `paste`,
    `comm`, `uniq`, `column`, `bc`, `xargs`, `realpath`, `readlink` replaced
    by core tools or bash builtins, so that pipelines stop mixing tools.
21. As the repo owner, I want `sed` used only for in-place edits, so that
    every other text transform is in `awk`.
22. As the repo owner, I want `basename`/`dirname` behind a named Commons
    path helper, so that path handling reads as words, not `${p%/*}`.
23. As the repo owner, I want consecutive `jq` calls on the same input merged
    when the merged filter stays short or uses named `def`s, so that one
    function's JSON logic sits in one place.
24. As the repo owner, I want no change traded for one fewer binary if it
    reads worse, so that tool reduction never fights readability.
25. As the repo owner, I want every `ADR NNNN` in the docs to be a relative
    link, so that I jump straight to the reasoning.
26. As the repo owner, I want ADR mentions in code comments kept as plain
    `(ADR NNNN)`, so that comments stay compact per Comment Style.
27. As the repo owner, I want `.scratch/` and vendored skills excluded from
    link rewriting, so that working tickets and upstream files aren't churned.
28. As the repo owner, I want the installer to behave exactly the same after
    each ticket, so that readability work never costs a broken install.
29. As the repo owner, I want host-profile keys, CLI flags, external env vars,
    target paths, and grep-able log/marker strings frozen, so that profiles,
    tests, and audits keep working.
30. As the repo owner, I want bugs found during the refactor filed as their
    own `.scratch` tickets, so that a rename diff never hides a fix.
31. As the repo owner, I want rename, tool, and split changes in separate
    commits per ticket, so that a pure-rename diff is trivial to review and
    bisect.
32. As the repo owner, I want a pilot ticket on the install entry script and
    its direct libs reviewed with me before the rollout, so that the style is
    calibrated on real code before 43k lines move.
33. As the repo owner, I want the remaining tickets in lifecycle order
    (bootstrap/wipe → layout + zfs → chroot → profiles → packages → config →
    guided, controller last → feature-audit → vm → tests), so that the
    install path is readable first.
34. As the repo owner, I want shellcheck, bats, `audit.sh`, and the
    Readability Lint green on every commit, so that regressions surface at
    the commit that caused them.
35. As the repo owner, I want a VM install closing each install-path ticket
    and a guided-flow run closing each guided ticket, so that real behaviour
    is proven, not just unit-tested.
36. As the repo owner, I want `CONTEXT.md` terms renamed first when a code
    rename touches one, so that glossary and code never disagree.
37. As the repo owner, I want ADRs left untouched by renames, so that they
    stay an honest point-in-time record.
38. As an agent implementing installer code, I want
    `docs/agents/readability.md` (rules, allowlist, Prefix Map, Tool Tiers),
    pointed to from `CLAUDE.md`, so that I write readable code first time.
39. As an agent, I want the Readability Lint to tell me the exact rule, file,
    and line I broke, so that I fix it without guessing.
40. As an agent, I want the lint to pass existing violations in the
    Readability Baseline but fail new ones, so that I'm held to the rules
    without fixing the whole repo first.
41. As the repo owner, I want the lint to fail when a Baseline entry no longer
    matches a violation, so that the baseline only ever shrinks.
42. As the repo owner, I want bats `@test` descriptions exempt from the
    naming lint, so that tests keep free-text titles.
43. As the repo owner, I want test helpers and bats files renamed in lockstep
    with the code they call, so that tests still exercise the real functions.
44. As the repo owner, I want program payloads (`programs/*/home/…`) out of
    scope, so that upstream-shaped configs aren't renamed into breakage.

## Implementation Decisions

- **Ticket 0 — foundations.** ADR 0153 (done) and glossary terms (done);
  `docs/agents/readability.md` with the rules, acronym allowlist, Tool Tiers,
  Interface Function list, and the full **Prefix Map** (every current file →
  new public/private Prefix) for one owner approval; a "Readability" pointer
  section in root `CLAUDE.md`, cross-linked with Comment Style; the
  Readability Lint + its bats test + the initial Readability Baseline.
- **Readability Lint shape.** A bash + awk script beside the no-python gate,
  run over tracked files. Checks, each reported as `rule: file:line: detail`:
  - abbreviation denylist tokens in function and `local` names (allowlist:
    domain acronyms, `i`, `j`, `rc`);
  - function name Prefix matches the Prefix Map entry for its file, unless
    the name is a listed Interface Function;
  - function length > ~50 lines; nesting depth > 3;
  - file length > 500 lines;
  - replace-tier tools invoked; `sed` without `-i`;
  - unlinked `ADR NNNN` in in-scope `.md` files.
- **Ratchet.** The Readability Baseline is a committed plain-text list of
  violation keys (rule + file + symbol; not line numbers, so unrelated edits
  don't churn it). Lint fails on any violation not in the baseline and on any
  baseline entry no longer violated. Tickets delete entries as they fix them.
- **Prefix rule.** Prefix = file stem (`config/history.sh` → `history_`);
  when a directory forms one public API, public functions take the directory
  name and private ones `_<file stem>_`. Interface Functions take the glossary
  role name and are the only exception.
- **Function name shape.** Actions `<prefix>_<verb>_<object>`; predicates
  `<prefix>_is_/has_/can_…` return status and print nothing; producers are
  noun-named for their output.
- **Flow outline.** Each entry script's `main()` sits near the top and calls
  phase functions only; lib headers gain `Used by:`. `ARCHITECTURE.md` links
  to the `main()`s.
- **Tool Tiers.** Core: bash builtins, `jq`, `awk`, `grep`, `sort`, file ops
  (`mkdir cp mv rm ln find mktemp`). `sed` only in-place. Replace-tier tools
  rewritten. New path helpers (parent dir, base name) go in the right world
  per Shell Commons — Installer Stdlib for host-side code, the chroot common
  library inside `arch-chroot`, Shell Stdlib for program scripts — never
  merged across worlds.
- **jq consolidation.** Merge consecutive `jq` reads of one input into one
  program only when the result stays short or is factored with named `def`s.
- **File splits.** Split by responsibility; each new file gets its own
  Prefix from the Prefix Map (map updated in the same ticket, owner
  re-approval only for new public Prefixes).
- **Frozen interface.** Host-profile JSON keys, CLI flags, externally read
  env vars, paths written on the target, and any string a test, audit, or
  Known Noise pattern greps for. Renaming an exported var used across the
  source boundary is allowed only when every reader is inside `.installer/`.
- **Glossary lockstep.** When a rename exposes or changes a domain term,
  `CONTEXT.md` is edited first in the same commit. ADRs are never edited.
- **ADR linking.** One ticket rewrites `ADR NNNN` mentions in every tracked
  `.md` (excluding `docs/adr/` — optional, may include — `.scratch/`,
  vendored `.agents/skills/`) to relative links to the ADR file. Code
  comments keep the plain anchor.
- **Commit shape.** Per ticket: separate commits for renames, tool/jq
  changes, and splits; conventional commits, single line.
- **Ticket order.** 0 foundations → 1 ADR links → 2 pilot (install entry
  script + direct libs), then style review and doc adjustment → 3+ lifecycle
  order, guided controller last in the guided group.

## Testing Decisions

- **Good tests assert behaviour at the highest seam**: what the lint reports
  for a repo state, what the installer does — never internal helper shapes.
- **New seam (the only one): the Readability Lint run on a repo.** Prior art:
  the no-python gate and its bats test. Headline test: lint on this repo is
  clean against the Readability Baseline. Fixture tests build throwaway git
  repos and assert each rule is caught with its `rule: file:line` message —
  abbreviation in a function / local name, wrong or missing Prefix, function
  and file over cap, deep nesting, replace-tier tool, `sed` without `-i`,
  unlinked ADR in a doc, new violation absent from baseline, stale baseline
  entry. And that allowed cases pass: domain acronyms, `i`/`j`/`rc`,
  Interface Functions, `sed -i`, ADR mentions in `.scratch/` or code
  comments, bats `@test` titles, jq `def` look-alikes.
- **Behaviour preservation: existing seams only.** The full bats suite,
  shellcheck, and `audit.sh` on every commit; a VM install per install-path
  ticket; a guided-flow run (VM Agent Control) per guided ticket. Bats tests
  that call renamed functions are renamed in lockstep, never deleted or
  weakened.
- **New Commons path helpers** get unit tests in the existing stdlib bats
  files for their world.

## Out of Scope

- Program payloads under `programs/*/home/` (upstream-shaped configs).
- Anything outside `.installer/` except the docs touched for ADR links, the
  agent doc, and `CLAUDE.md`.
- Behaviour changes or bug fixes (filed as separate tickets).
- Renaming frozen interfaces (config keys, CLI flags, external env vars,
  target paths, grep-able strings).
- Editing ADRs; trimming `CONTEXT.md` or consolidating ADRs.
- Rewriting comments beyond keeping them consistent with renamed code
  (Comment Style already governs that).

## Further Notes

- The Prefix Map is the largest single approval; expect `fa_` →
  `feature_audit_`, `_ctl_` → `_controller_`, `blcommon_`/`_bl_` →
  `bootloader_common_`, `cfgstate_` → `config_state_`, `cfgstore_` →
  `config_store_`, `ca_` → `config_apply_`, `hist_` → `history_`, `_noc_` →
  `noctalia_preset_`, `_lm_` → `live_medium_`, `imp_` → impermanence-common
  stem, `_nzroot_` → non-ZFS root stem, `_root_*`/`_data_*` →
  `root_adapter_*`/`data_formatter_*`.
- Collisions to resolve in the map: `install_` is used by both config
  accessors (`install_config_*`) and install-state; `_guided_` and `_ctl_`
  share the guided directory.
- Tool counts at spec time (approx.): jq 887 uses, grep 192, awk 98, dirname
  85, sed 80, sort 65, head 57, basename 47, tail 38, tr 34, cut 31.
