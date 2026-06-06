Status: done

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

## Comments

Implemented. `profiles.sh`→`lib/profiles/runner.sh`, `run-program.sh`→
`lib/profiles/program-runner.sh`. The runtime-staging references in
`runner.sh` (`_STAGED_RUNTIME_FILES` entry, `chmod`, both chroot-exec
paths in the system + user-program paths) all carried the
`lib/run-program.sh` literal, so the rename caught them; added a
per-file `mkdir -p "$(dirname …)"` in the staging loop so the nested
`lib/profiles/` staged path is created. `program-runner.sh` sources via
`$SHELL_COMMONS` (env), no relative-path breakage. Program install.sh
doc-comments updated. `audit.sh` §7 reads the manifest from the new
path — still 82/82.

Found+fixed 2 false-pass tests in `profiles-aur.bats`: a bare
`OS_DIR="$BATS_TEST_DIRNAME/.."` (no trailing slash) wasn't caught by
the depth-bump regex, so it resolved to `.os/tests` not `.os` — the
"octopi via real adapter" test genuinely failed; its sibling passed
vacuously (KDE-owned pkg absent either way). Both now `../..`.

3 tests relocated to `tests/profiles/`. Verified: bats **917/0**,
`audit.sh` **82/82**, `shellcheck.sh` clean.
