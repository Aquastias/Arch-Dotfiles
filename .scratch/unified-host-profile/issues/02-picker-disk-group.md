# Picker disk→group assignment

Status: done

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Teach the Pre-Install Picker to map operator-picked disks onto the pool
structure declared in the profile. The profile carries the full pool
skeleton — `os_pool` + `storage_groups` + `data_pools` with
names/topology/mount/ashift/owners — but no device fields. The picker
prompts for the profile and the disks, assigns picked disks onto the
declared groups, and validates the assignment against the existing
min-disk table before producing the effective config in tmpfs.

This is a deep, libvirt-free module: given a declared pool skeleton + a
set of picked disks, compute the device assignment or fail with a clear
message.

## Acceptance criteria

- [x] The schema accepts a profile pool skeleton (`os_pool` +
      `storage_groups` + `data_pools`) with names/topology/mount/ashift/
      owners and NO device fields.
- [x] The picker assigns picked disks onto the declared groups
      (`picker_assign_disks`, per-group model). *Interactive prompting
      for profile/disks → issue 03 (scope: pure module only).*
- [x] Assignment is validated against the min-disk table (mirror/stripe
      ≥2, raidz1 ≥3, raidz2 ≥4); an under-populated group fails with a
      clear message that names the group.
- [x] Single mode resolves exactly one OS device.
- [x] The effective config (skeleton + assigned devices) is produced (to
      stdout). *Writing it into tmpfs is the caller's job → issue 03.*
- [x] bats: Picker disk→group (assignment + min-disk validation), no
      libvirt.

## Comments

Implemented the libvirt-free deep module `picker_assign_disks
<profile_json> <assignment_json>` in `.os/lib/picker.sh` (per-group
assignment model, agreed with operator): single mode resolves exactly one
OS device; multi mode validates every declared group's picked-disk count
against the min-disk table (`picker_validate_layout`) before merging
devices into the skeleton, naming the offending group on failure.

Scope was pure-module-only by decision; interactive per-group prompting +
tmpfs production land in issue 03 (`install-profile-frontend`). Cross-check
in `profile-loader.bats`: a device-less skeleton and a picker-assigned
effective config both validate against the issue-01 closed schema.

Tests: `.os/tests/picker-assign.bats` (8) + 2 cross-checks in
`profile-loader.bats`. Full suite green (998).

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`
