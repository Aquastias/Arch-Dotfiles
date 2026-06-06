Status: done

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

## Comments

Implemented. `zfs-module/zfs-pools/zfs-verify/pool-owners.sh` →
`lib/zfs/{module,pools,verify,pool-owners}.sh`. Refs updated:
`03-install.sh`, `01-bootstrap-zfs.sh` (zfs-module), `audit.sh` manifest
(zfs-pools), and the `tests/layout/` tests that source zfs-pools +
pool-owners. No internal sibling sources. Public function names
unchanged; ADR 0028/0031 preserved.

4 zfs tests relocated to `tests/zfs/` with `../`→`../../` bump.
Verified: bats **917/0**, `audit.sh` **82/82**, `shellcheck.sh` clean.
