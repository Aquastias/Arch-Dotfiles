Status: ready-for-agent

# ZFS modules → lib/zfs/

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Group the ZFS files into a new `lib/zfs/` folder, update every
`source`/path reference, and relocate their tests to the mirrored
`tests/zfs/` path. Move only — no behavior change, no function renames.

Rename mapping:

```
zfs-module.sh -> zfs/module.sh
zfs-pools.sh  -> zfs/pools.sh
zfs-verify.sh -> zfs/verify.sh
pool-owners.sh -> zfs/pool-owners.sh
```

Pools-by-stable-device-paths (ADR 0028) and Pool Owners ACLs (ADR 0031)
are preserved — files move only.

## Acceptance criteria

- [ ] 4 ZFS files moved into `lib/zfs/` per the mapping
- [ ] Every `source`/path reference updated repo-wide
- [ ] All public function names unchanged
- [ ] Tests relocated to mirrored `tests/zfs/` paths
- [ ] Full bats suite passes unchanged (no behavior change)

## Blocked by

- None - can start immediately
