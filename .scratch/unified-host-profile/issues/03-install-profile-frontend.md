# install.sh --profile end-to-end + unattended seam

Status: ready-for-agent

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Wire the two front-ends onto the one back-end. `install.sh --profile
<name>` becomes the user-facing interactive install: `load_profile` →
picker disk resolution → effective config in tmpfs → the existing
back-end that consumes an assembled config. The positional
`<config-file>` form remains the unattended seam the VM cloud-init seed
already injects, reused unchanged. The `host_profile` field is dropped
from the schema — the directory name / `--profile` arg is the identity.

## Acceptance criteria

- [ ] `install.sh --profile <name>` runs a full interactive install via
      load_profile → picker → tmpfs effective config → back-end.
- [ ] The positional `<config-file>` form still works as the unattended
      seam (the VM seed path).
- [ ] The `host_profile` field is removed from the schema and no longer
      read.
- [ ] No committed assembled config is required; the effective config is
      transient.
- [ ] Verified end-to-end by a VM install via `--profile`.

## Blocked by

- `.scratch/unified-host-profile/issues/02-picker-disk-group.md`
