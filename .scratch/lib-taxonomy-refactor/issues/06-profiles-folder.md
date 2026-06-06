Status: ready-for-agent

# Profile runners → lib/profiles/

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Group the profile-execution files into a new `lib/profiles/` folder,
update every `source`/path reference, and relocate their tests to the
mirrored `tests/profiles/` path. Move only — no behavior change, no
function renames.

Rename mapping:

```
profiles.sh    -> profiles/runner.sh
run-program.sh -> profiles/program-runner.sh
```

## Acceptance criteria

- [ ] 2 profile files moved into `lib/profiles/` per the mapping
- [ ] Every `source`/path reference updated repo-wide
- [ ] All public function names unchanged
- [ ] Tests relocated to mirrored `tests/profiles/` paths
- [ ] Full bats suite passes unchanged (no behavior change)

## Blocked by

- None - can start immediately
