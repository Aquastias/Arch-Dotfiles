# Rewrite ARCHITECTURE.md diagrams + CONTEXT.md glossary

Status: ready-for-human

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

- [ ] `ARCHITECTURE.md` diagrams collapse the three host inputs into one
      profile and drop the template → `install.jsonc` node.
- [ ] `CONTEXT.md`: Host Profile redefined as the unified `profile.jsonc`;
      Install Config + Install Template retired; Pre-Install Picker,
      Single Entry Point, User Config, VM Profile updated; pending-redesign
      note removed from Flagged ambiguities.
- [ ] Human confirms the diagrams read clearly.

## Blocked by

- `.scratch/unified-host-profile/issues/10-big-bang-cleanup.md`
