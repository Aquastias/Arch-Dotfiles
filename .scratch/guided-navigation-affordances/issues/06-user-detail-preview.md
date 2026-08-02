# User detail preview

Status: ready-for-agent

## Parent

`.scratch/guided-navigation-affordances/PRD.md`

## What to build

Hovering a user row on the Users screen shows a side panel with that user's full
detail: shell, sudo, groups, programs (list/count), git identity if set,
and SSH-key count. Values are effective (User Core merged, session overrides
applied); a session-created user shows its in-progress editor-form state. This
adds the Users values screen to the set that shows a preview panel.

## Acceptance criteria

- [ ] Hovering a user row renders shell, sudo, groups, programs, and
      (when set) git identity and SSH-key count.
- [ ] The panel shows effective values (core-merged, override-applied), matching
      what will install.
- [ ] A session-created user's panel reflects its in-progress editor-form state.
- [ ] The Users values screen is registered as having a preview panel.
- [ ] Covered headless via `guided_ctl_preview <line>` with the nav set to the
      Users screen; prior art: `tests/config/guided-users.bats`,
      `guided-userforms.bats`.

## Blocked by

- None — the Users screen exists today.
