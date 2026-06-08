# Runner reconciliation + user_services

Status: ready-for-agent

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Soften the Runner's program-reference rule and add a user-level service
list. A user-level program sharing a name with a host program installs at
user level (shadow). A user referencing a system program the host already
installs is a no-op. A user referencing a system program no host installs
aborts with an actionable message (the `system` flag stays host-owned —
programs are unchanged). A user profile's `user_services` list is enabled
via `systemctl --user enable` after the user's programs + dotfiles are in
place; a unit not found at enable-time aborts with an actionable message.

## Acceptance criteria

- [ ] A user-level program sharing a name with a host program installs at
      user level (shadow).
- [ ] A user referencing a system program the host already installs is a
      no-op (no abort, no reinstall).
- [ ] A user referencing a system program no host installs aborts with an
      actionable message.
- [ ] The `system` flag stays host-owned (program specs unchanged).
- [ ] A `user_services` list is enabled via `systemctl --user enable`
      after user programs + dotfiles are placed.
- [ ] A `user_services` unit not found at enable-time aborts with an
      actionable message.
- [ ] bats: Runner reconciliation (all four program cases + user_services
      abort).

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`
