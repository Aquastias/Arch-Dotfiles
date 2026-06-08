# Picker disk→group assignment

Status: ready-for-agent

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

- [ ] The schema accepts a profile pool skeleton (`os_pool` +
      `storage_groups` + `data_pools`) with names/topology/mount/ashift/
      owners and NO device fields.
- [ ] The picker prompts for the profile, then the disks, then assigns
      picked disks onto the declared groups.
- [ ] Assignment is validated against the min-disk table (mirror/stripe
      ≥2, raidz1 ≥3, raidz2 ≥4); an under-populated group fails with a
      clear message.
- [ ] Single mode resolves exactly one OS device.
- [ ] The effective config (skeleton + assigned devices) is produced in
      tmpfs.
- [ ] bats: Picker disk→group (assignment + min-disk validation), no
      libvirt.

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`
