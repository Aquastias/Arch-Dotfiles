# Profile deep-tree preview

Status: ready-for-agent

## Parent

`.scratch/guided-navigation-affordances/PRD.md`

## What to build

Hovering a profile row in the Profiles picker shows a deep ASCII tree of that
machine, replacing the current header-comment-only preview. The tree renders the
resolved (Host-Core-merged) profile down to its leaves: hostname; users expanded
to shell·groups; options including kernel, bootloader, encryption, impermanence,
swap, ssh; environment (desktop/gpu); security; backup; and disk skeleton. It
reuses the existing layout-graph tree rendering style so previews feel
consistent. Profile rows stay clean (name + `▸`) — all detail lives in
the preview pane.

## Acceptance criteria

- [ ] Hovering a committed profile row renders a nested tree containing the
      hostname, at least one user expanded to shell·groups, and the
      encryption/impermanence options.
- [ ] The tree also surfaces environment, security, backup, and disk skeleton.
- [ ] Values shown are the resolved profile (merged over Host Core), not the raw
      on-disk delta.
- [ ] The tree uses the same ASCII tree style as the disk-layout preview.
- [ ] Profile rows show only the name (and `▸`); no inline user/hostname hint.
- [ ] Covered headless via `guided_ctl_preview <line>` with the nav set to the
      profiles screen; prior art: `tests/config/guided-profiles-menu.bats`
      (preview), the layout-graph tests.

## Blocked by

- None — enhances the existing profiles preview.
