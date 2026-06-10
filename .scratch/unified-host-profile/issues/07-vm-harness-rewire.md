# VM harness rewire

Status: done

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

- [x] A VM Profile's `host_profile` resolves through the picker to the
      unified `profile.jsonc`.
- [x] The "host ships no `install.template.jsonc`" validation check is
      removed.
- [x] `install: "repo"` resolves to the profile named by
      `VM_DEFAULT_HOST_PROFILE` (default `desktop`).
- [x] `vm/lib/profile.sh` + `profile-validate.sh` tests updated and
      green.

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`

## Comments

### Agent (TDD)

`vm/lib/profile.sh` now sources `lib/config/profile.sh` (one bootstrap →
`load_profile` + `assemble_profile_config`, transitively picker/layers),
so a VM resolves the unified profile via the *same* seam the real
`install.sh --profile` uses — no copied template.

- `_profile_resolve_host` → `load_profile <host>` → mode from the loaded
  profile's pin (`single`, or `multi`→its `os_pool.topology`) else the
  VM's `layout.mode` (default single) → map disk count to `/dev/sdX` →
  `assemble_profile_config`. Hostname falls back to the host-dir name
  (ADR 0036: dir ≡ hostname), which drives `load_host_config` software.
- **Decision X**: multi topology comes only from the profile's `os_pool`
  pin (every real multi host pins it — arch-secure mirror). Unpinned +
  a multi `layout.mode` is rejected, not synthesized — the only way to
  keep it was to re-inline the assembler, undoing the single-seam reuse.
- `install:"repo"` ≡ `host_profile: $VM_DEFAULT_HOST_PROFILE` at single
  (`${VM_DEFAULT_HOST_PROFILE:-desktop}`, env-overridable). Tested by
  equivalence — survives the loss of `install.jsonc` (issue 10).
- Validation: dropped the `install.template.jsonc` check for a
  host-directory existence guard (typos still fail fast).
- `profile_resolve_config` pruned to one arg; `vm.sh` no longer reads
  `install.jsonc` (decouples it from issue 10's deletion).

Injected `INSTALL_CONFIG_CONTENT` now carries machine+software — harmless:
the unattended path validates only machine fields (no closed-schema
rejection) and the runner loads software by hostname.

Full suite green (1039/1039), shellcheck clean.
