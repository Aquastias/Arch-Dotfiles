Status: ready-for-agent

# Disk Wipe modules → lib/wipe/ (move only)

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Move the Disk Wipe support files into a new `lib/wipe/` folder, update
every `source`/path reference (including from `02-wipe.sh`), and
relocate their tests to the mirrored `tests/wipe/` path. **Move only** —
thinning `02-wipe.sh` and extracting prior-state is a later slice
(issue 08). No behavior change, no function renames.

Rename mapping:

```
wipe-method.sh  -> wipe/method.sh
wipe-targets.sh -> wipe/targets.sh
progress.sh     -> wipe/progress.sh
```

## Acceptance criteria

- [ ] 3 wipe files moved into `lib/wipe/` per the mapping
- [ ] Every `source`/path reference updated, including `02-wipe.sh`
- [ ] All public function names unchanged
- [ ] Tests relocated to mirrored `tests/wipe/` paths
- [ ] Full bats suite passes unchanged (no behavior change)

## Blocked by

- None - can start immediately
