Status: done

# Runtime tool: `add` / `remove`

## Parent

`.scratch/impermanence/PRD.md`

## What to build

A new tool in `tools/` that lets the operator add and remove Persist Extensions on a running impermanent system without re-running the installer. The tool is config-first: it writes the path into the host config jsonc as the source of truth, then materializes the live artifacts to match.

Scope:

- Two verbs: `add <path>` and `remove <path>`. Invoked via the repo's tool-running convention (matching `tools/save-pkglist.sh` and `tools/install-pkglist.sh`).
- `add <path>`:
  - Refuses to operate if impermanence is not enabled on the running system (no `/persist` dataset present), with a clear error.
  - Refuses to operate on a Curated Persist Default (looked up via `/usr/lib/impermanence/defaults.manifest`), with a message telling the user that curated defaults are vendor-shipped and managed via `apply-defaults`.
  - Detects whether the path exists as a directory or file on disk; rejects paths that don't exist (an operator must create the path before declaring it persistent — same semantics as the install-time validator).
  - Edits `hosts/<hostname>/config.jsonc` to append the path into `persist.directories` or `persist.files`, preserving comments and formatting (the existing `lib/jsonc.sh` is the right primitive).
  - Copies the live data from the path onto the Persist Dataset (`/persist/<path>`), preserving ownership and modes.
  - Generates a Persist Mount unit at `/persist/etc/systemd/system/persist-<slug>.mount` and appends a tmpfiles entry to `/persist/etc/tmpfiles.d/impermanence-extensions.conf`.
  - Runs `systemctl daemon-reload && systemctl start persist-<slug>.mount`.
  - Reports success with the slug and the mount unit name.
  - Idempotent: re-running `add` on an already-persisted path is a no-op with a notice.
- `remove <path>`:
  - Symmetric to `add`. Stops and disables the Persist Mount, removes the unit file and tmpfiles entry, optionally moves the data back from `/persist` to the live path (operator-confirmed), updates the host config jsonc.
  - Refuses to remove a Curated Persist Default, same message as `add`.
  - Reports what was removed.
  - Idempotent: re-running `remove` on a path that isn't currently persisted is a no-op with a notice.
- A bats unit suite `tests/impermanence-tool.bats` exercising both verbs against a fixture tmpdir. Mock `systemctl`, `zfs`, and the filesystem layout. Assert: jsonc edit is correct, unit file content is correct, tmpfiles content is correct, data is moved (and on `remove`, moved back when confirmed), idempotency holds, error paths fire (path doesn't exist; path is a curated default; impermanence not enabled).
- The tool sources the Curated Persist Defaults bash arrays from the same module that generates them at install time. There is exactly one source-of-truth for the curated list.

The `status` and `apply-defaults` verbs are slice 5; this slice ships only `add` and `remove`.

## Acceptance criteria

- [x] `tools/impermanence.sh add <path>` writes the host config jsonc, copies data, generates the Persist Mount + tmpfiles entry, and reloads systemd
- [x] `tools/impermanence.sh remove <path>` reverses the above, with operator confirmation before moving data back
- [x] Both verbs refuse to operate on Curated Persist Default paths
- [x] Both verbs refuse to operate when impermanence is not enabled on the running system
- [x] jsonc edits preserve comments and formatting (use the existing jsonc primitive)
- [x] Both verbs are idempotent
- [x] `tests/impermanence-tool.bats` covers happy paths, error paths, and idempotency for both verbs with mocked external commands

## Blocked by

- `.scratch/impermanence/issues/02-persist-extensions.md`
