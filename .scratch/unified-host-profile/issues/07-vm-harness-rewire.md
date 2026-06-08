# VM harness rewire

Status: ready-for-agent

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Point the VM Harness at the unified profile. A VM Profile's
`host_profile` resolves through the picker to the unified `profile.jsonc`
(via the loader/assembler), and the "host ships no
`install.template.jsonc`" validation check is dropped. The `install:
"repo"` source is redefined to mean "the designated default profile,"
named by a single harness constant `VM_DEFAULT_HOST_PROFILE` (default
`desktop`).

## Acceptance criteria

- [ ] A VM Profile's `host_profile` resolves through the picker to the
      unified `profile.jsonc`.
- [ ] The "host ships no `install.template.jsonc`" validation check is
      removed.
- [ ] `install: "repo"` resolves to the profile named by
      `VM_DEFAULT_HOST_PROFILE` (default `desktop`).
- [ ] `vm/lib/profile.sh` + `profile-validate.sh` tests updated and
      green.

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`
