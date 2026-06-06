Status: done

# Layout Module → lib/layout/ (move only)

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Move the Layout Module files into a new `lib/layout/` folder, update
every `source`/path reference, and relocate their tests to the mirrored
`tests/layout/` path. **Move only** — the planner/executor split is a
later slice (issue 09). No behavior change, no function renames.

Rename mapping:

```
layout-common.sh -> layout/common.sh
layout-single.sh -> layout/single.sh
layout-multi.sh  -> layout/multi.sh
```

Preserve the existing wiring: the active layout adapter is selected by
`INSTALL_MODE` and sourced from `03-install.sh` **before**
`validate_install_context` runs so `layout_validate` can be called on
the active adapter. Phase lifecycle (ADR 0016) and adapter-owns-
validation (ADR 0014) are preserved — only the paths change.

## Acceptance criteria

- [ ] 3 layout files moved into `lib/layout/` per the mapping
- [ ] Every `source`/path reference updated, including the pre-validate
      sourcing in `03-install.sh`
- [ ] All public function names unchanged (`layout_validate`,
      `layout_plan`, `layout_partition`, `layout_create_pools`,
      `layout_mount_esp`, `_layout_enter_phase`, `_layout_exit_phase`)
- [ ] Tests relocated to mirrored `tests/layout/` paths
- [ ] Full bats suite passes unchanged (no behavior change)

## Blocked by

- None - can start immediately

## Comments

Implemented. `layout-common/single/multi.sh` → `lib/layout/{common,
single,multi}.sh`. The **dynamic** source at `03-install.sh:174` updated
to `lib/layout/${INSTALL_MODE}.sh`. `single.sh`/`multi.sh` source
`common.sh` as a same-dir sibling (path rename `layout-common.sh`→
`common.sh`, still `./`). `<mode>` placeholder comments in `globals.sh`,
`03-install.sh`, `config/lifecycle.sh` updated to `lib/layout/<mode>.sh`.
`audit.sh` manifest updated. Public function names unchanged; phase
lifecycle (ADR 0016) and adapter-owns-validation (ADR 0014) preserved.

3 layout tests relocated to `tests/layout/` with `../`→`../../` bump.
Verified: bats **917/0**, `audit.sh` **82/82**, `shellcheck.sh` clean,
no stale `lib/layout-` refs.
