# Runner reconciliation + user_services

Status: done

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

- [x] A user-level program sharing a name with a host program installs at
      user level (shadow).
- [x] A user referencing a system program the host already installs is a
      no-op (no abort, no reinstall).
- [x] A user referencing a system program no host installs aborts with an
      actionable message.
- [x] The `system` flag stays host-owned (program specs unchanged).
- [x] A `user_services` list is enabled via `systemctl --user enable`
      after user programs + dotfiles are placed (offline equivalent: a
      symlink into `default.target.wants`, as the chroot has no session).
- [x] A `user_services` unit not found at enable-time aborts with an
      actionable message.
- [x] bats: Runner reconciliation (all four program cases + user_services
      abort).

## Comments

The reconciliation decision is a pure, unit-tested function
`reconcile_user_program <name> <host_system_program...>` (lib/config/
layers.sh): system:false → `user` (install at user level / shadow);
system:true + host installs → `noop`; system:true + no host → abort;
unknown → abort. `validate_program` stays the contract primitive (unchanged
+ still tested); the preflight (validation.sh) and the runner's user-program
loop now reconcile instead of blanket-rejecting.

User-profile `user_services[]` (new user schema key) enabled by
`_profiles_enable_profile_user_services` after programs + dotfiles, via the
unit-resolver `_profiles_resolve_user_unit`; a missing unit aborts (vs. the
per-program list, which skips). The symlink/enable runs in the chroot
(VM-verified); the reconcile decision, unit resolution, and abort are
unit-tested.

Tests: +1 profile-loader (user_services schema), +4 configs (reconcile
cases), +5 profiles-user-services (resolver + enable/abort/no-op). Full
suite green (1031).

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`
