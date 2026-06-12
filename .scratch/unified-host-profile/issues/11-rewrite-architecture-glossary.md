# Rewrite ARCHITECTURE.md diagrams + CONTEXT.md glossary

Status: done

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Make the docs match the unified model — the original goal of the whole
effort. Collapse the `ARCHITECTURE.md` diagrams so the three host inputs
become one `profile.jsonc` and the template → `install.jsonc` assembly
node disappears. In `CONTEXT.md`, redefine Host Profile as the unified
`profile.jsonc`, retire the Install Config + Install Template entries,
update Pre-Install Picker / Single Entry Point / User Config / VM Profile,
and remove the pending-redesign note from Flagged ambiguities. HITL: a
human confirms the diagrams read clearly ("explain it like I'm 5").

## Acceptance criteria

- [x] `ARCHITECTURE.md` diagrams collapse the three host inputs into one
      profile and drop the template → `install.jsonc` node.
- [x] `CONTEXT.md`: Host Profile redefined as the unified `profile.jsonc`;
      Install Config + Install Template retired; Pre-Install Picker,
      Single Entry Point, User Config, VM Profile updated; pending-redesign
      note removed from Flagged ambiguities.
- [x] Human confirms the diagrams read clearly.

## Blocked by

- `.scratch/unified-host-profile/issues/10-big-bang-cleanup.md`

## Comments

- Done (AC1+AC2+AC3). Human confirmed diagrams read clearly;
  `user cfg → user profile` fixed in D2 during review. CONTEXT.md
  reflowed to ≤80 cols (content unchanged). File is at
  `.os/ARCHITECTURE.md` (issue said root).
- AC1: 4 mermaid diagrams rewritten. D1 — one host input
  (`profile.jsonc`), live-CD fork now `--profile` (interactive, picker
  picks disks) vs `<config-file>` (unattended/VM seed) → one ephemeral
  effective config. D3 — `install.template.jsonc → pick.sh →
  install.jsonc` node removed; host/user `profile.jsonc` core+specific →
  effective, picker folds operator-picked disks into the effective
  config. D2 — dropped `host_profile`, locale/keymap now arrays. D4 —
  User Config → User Profile. All 4 re-render via `mmdc`.
- AC2: beyond the 7 named entries, swept every cross-ref to retired
  terms so the glossary stays coherent — retired Host Config (folded
  into Host Profile), renamed User Config → User Profile, added
  Effective Config, `config.jsonc → profile.jsonc` / `disks →
  disk_count` / `aur` now categorized / `host_profile` field dropped /
  `pick.sh` removed across ~25 entries.
- DEVIATION: CONTEXT.md keeps its one-long-line-per-entry convention
  (not 80-col wrapped) for consistency + grep-ability; ARCHITECTURE.md
  prose wrapped ≤80 per its own convention.
