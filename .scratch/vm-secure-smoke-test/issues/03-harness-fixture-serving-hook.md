Status: done

# Add VM_FIXTURE_FILES hook to the VM harness

## Parent

`.scratch/vm-secure-smoke-test/PRD.md` (ADR 0019)

## What to build

Extend `.os/vm/_harness.sh` with a declarative
`VM_FIXTURE_FILES` array. Each entry is a path (absolute, or
relative to the calling script's directory) to a file that
should be staged into `${CACHE_DIR}` before the python HTTP
server starts. The existing server (bound to
`${LIBVIRT_GATEWAY}:${HTTP_PORT}`, default
`192.168.122.1:9876`) then serves each staged file at
`http://${LIBVIRT_GATEWAY}:${HTTP_PORT}/<basename>` alongside
the existing `/run` installer script.

Behaviour contract:

- If `VM_FIXTURE_FILES` is unset or empty, nothing changes —
  the existing three `vm/*.sh` scripts continue to work
  identically.
- Each path is resolved relative to the calling script's
  directory if not absolute (matching the
  `BASH_SOURCE`/source dirname pattern used elsewhere in the
  harness).
- A missing source file aborts with `error` and a message
  that names the offending path. No silent skip.
- Each file is copied (not symlinked) into `${CACHE_DIR}` so
  cleanup goes through the same trap that already manages
  `${CACHE_DIR}`.
- A name collision between two `VM_FIXTURE_FILES` entries
  (same basename) aborts with a clear error.
- A collision between a fixture basename and the existing
  `/run` filename aborts with a clear error.

A bats test under `.os/tests/` drives the staging function in
isolation — no libvirt, no HTTP server, no python. It sets
`VM_FIXTURE_FILES` to a temp file with known contents, sets
`CACHE_DIR` to a tmpdir, invokes the staging function, and
asserts presence + byte-identity. Edge cases (missing file,
basename collision, `/run` collision) get their own
assertions.

This slice does not touch any `vm/*.sh` script — it only
extends the harness so future scripts can opt in.

## Acceptance criteria

- [ ] `_harness.sh` reads `VM_FIXTURE_FILES` (default empty
      array) and stages each entry into `${CACHE_DIR}` before
      the HTTP server starts.
- [ ] Existing `vm-kde.sh`, `vm-hyprland.sh`,
      `vm-kde-hyprland.sh` continue to run with no
      modification — the new code is a no-op when
      `VM_FIXTURE_FILES` is unset or empty.
- [ ] Relative paths in `VM_FIXTURE_FILES` are resolved
      relative to the calling script's directory, not the
      harness's directory.
- [ ] A missing source file aborts with `error` and a
      message naming the path.
- [ ] A duplicate basename across two `VM_FIXTURE_FILES`
      entries aborts with `error`.
- [ ] A fixture whose basename collides with `run` aborts
      with `error`.
- [ ] Staged files are copied (not symlinked) into
      `${CACHE_DIR}` and removed with the rest of
      `${CACHE_DIR}` by the existing cleanup trap.
- [ ] A bats test exercises the staging function in
      isolation (no libvirt, no HTTP). It covers: happy path
      with one entry, happy path with multiple entries,
      missing-file failure, duplicate-basename failure, and
      `/run` collision failure.
- [ ] `shellcheck` passes on `_harness.sh` and any new
      shell file.
- [ ] Full bats suite passes.
- [ ] Single commit, conventional-commit style, capitalized
      after the prefix.

## Blocked by

None - can start immediately.
