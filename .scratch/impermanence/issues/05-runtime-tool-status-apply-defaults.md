Status: done

# Runtime tool: `status` / `apply-defaults`

## Parent

`.scratch/impermanence/PRD.md`

## What to build

Add the inspection and curated-defaults-refresh verbs to the runtime tool. After this slice, the tool's verb set is complete: `add`, `remove`, `status`, `apply-defaults`.

Scope:

- `status`:
  - Refuses to operate if impermanence is not enabled (same check as `add`/`remove`).
  - Prints active Persist Mounts (the `systemctl list-units 'persist-*.mount'` set), distinguishing curated defaults (under `/usr/lib/`) from extensions (under `/persist/etc/systemd/system/`).
  - For each Rollback Dataset, runs `zfs diff rpool/ROOT/<ds>@blank rpool/ROOT/<ds>` and summarises drift (count of added/changed paths, optionally listing them with a `--verbose` flag if cheap; otherwise just a count and the command an operator can run to see details).
  - Returns non-zero if any Rollback Dataset is missing `@blank` (mirrors the boot-time fail-closed posture — `status` surfaces the same defect before reboot).
- `apply-defaults`:
  - Refuses to operate if impermanence is not enabled.
  - Reads the Curated Persist Defaults bash arrays from the chroot module (single source of truth).
  - Diffs the current arrays against `/usr/lib/impermanence/defaults.manifest`:
    - Paths in arrays but not in manifest → new; generate the `.mount` unit and tmpfiles entry under `/usr/lib/`, copy current live data into `/persist/<path>`, then bind.
    - Paths in manifest but not in arrays → removed; stop/disable the corresponding unit, delete the unit file and tmpfiles entry, but DO NOT move data back automatically (leave it on `/persist` for the operator to clean up; print where).
    - Paths in both → unchanged; no-op.
  - After the diff is applied, rewrite the manifest from the current arrays.
  - Run `systemctl daemon-reload` and start/stop the affected units.
  - Idempotent: running twice in a row produces no changes on the second run.
  - Operator-driven: run it after pulling an updated dotfiles repo to pick up new curated defaults the installer would have shipped.
- Extend `tests/impermanence-tool.bats` to cover both new verbs:
  - `status`: mocked `systemctl` and `zfs diff` outputs; verify formatting; verify the non-zero exit code on missing `@blank`.
  - `apply-defaults`: fixture with a manifest and a curated-arrays source; assert the diff produces correct add/remove operations; assert idempotency by running twice; assert the manifest is rewritten correctly.

## Acceptance criteria

- [ ] `tools/impermanence.sh status` lists active Persist Mounts (curated vs extension) and per-dataset drift summary
- [ ] `status` exits non-zero if any Rollback Dataset is missing `@blank`
- [ ] `tools/impermanence.sh apply-defaults` reads the curated arrays from the chroot module
- [ ] `apply-defaults` adds units for paths newly in the arrays, removes units for paths newly absent, leaves orphan data on `/persist` with a printed notice (no automatic data deletion)
- [ ] `apply-defaults` rewrites `/usr/lib/impermanence/defaults.manifest` after the diff is applied
- [ ] `apply-defaults` is idempotent (second run is a no-op)
- [ ] `apply-defaults` does NOT touch the Persist Extensions under `/persist/etc/systemd/system/`
- [ ] `tests/impermanence-tool.bats` covers both verbs' happy paths, idempotency, and the missing-`@blank` failure path

## Blocked by

- `.scratch/impermanence/issues/04-runtime-tool-add-remove.md`
