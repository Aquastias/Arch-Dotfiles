Status: ready-for-agent

# Package modules → lib/packages/

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Group the package-resolution files into a new `lib/packages/` folder,
update every `source`/path reference, and relocate their tests to the
mirrored `tests/packages/` path. Move only — no behavior change, no
function renames.

Rename mapping:

```
packages.sh     -> packages/list.sh
kernel.sh       -> packages/kernel.sh
iso-resolver.sh -> packages/iso-resolver.sh
```

Base Package List (ADR 0026), Kernel Selection + ZFS Module Guard
(ADR 0024), and archzfs-Compatible ISO (ADR 0023) are preserved — files
move only.

## Acceptance criteria

- [ ] 3 package files moved into `lib/packages/` per the mapping
- [ ] Every `source`/path reference updated repo-wide
- [ ] All public function names unchanged (e.g. `collect_packages`)
- [ ] Tests relocated to mirrored `tests/packages/` paths
- [ ] Full bats suite passes unchanged (no behavior change)

## Blocked by

- None - can start immediately
