Status: ready-for-agent

# Persist Extensions: declare and apply

## Parent

`.scratch/impermanence/PRD.md`

## What to build

Add the host-level mechanism for declaring additional persist paths beyond the Curated Persist Defaults. After this slice, an operator can declare `persist.directories` and `persist.files` in either Host Core or a specific Host Config (deep-merged), and the installer materializes those paths as Persist Mount units on the Persist Dataset.

Scope:

- Extend the host config schema with a `persist` object containing two arrays: `directories` (paths that should bind whole-directory) and `files` (single-file binds). Each entry is an absolute path. The two arrays are distinct because they translate to different tmpfiles types (`d` vs `f`).
- Add deep-merge of `persist` between Host Core and Host Config, matching the existing semantics for `sysctl` and `packages`.
- Add validation rules to the existing validation library following the established short-imperative style. Errors: path must be absolute; path must not contain `..` or `~`; entry in `files` must not be a directory on disk; entry in `directories` must not be a file on disk. Warnings: path under an already-persistent dataset (`/home`, `/var`, `/var/log`, `/var/cache`, `/tmp`) is redundant; path that overlaps a Curated Persist Default is redundant; persist declared while `options.impermanence.enabled=false` has no effect.
- Extend the Chroot Configuration Module from slice 1 to also generate Persist Extension units. Extension units live under `/persist/etc/systemd/system/` (the operator-editable location), not under `/usr/lib/`. Extension tmpfiles snippets go under `/persist/etc/tmpfiles.d/`. This is the only place the two-layer architecture matters at install time: curated defaults to `/usr/lib/`, extensions to `/persist/`.
- Move (not copy) each extension path's content onto the Persist Dataset before the existing `@blank` snapshot step. The move applies to extensions exactly as it does to curated paths — so the snapshot remains genuinely blank.
- Extend `tests/chroot-impermanence.bats` with cases for: extension unit generation, tmpfiles entries written to the correct location, deep-merge across Host Core and Host Config, the redundant-path warnings firing as expected, and the validation errors aborting the install.

The validation rules from the PRD's table go into the same library and follow the same idiomatic message style as existing validators (short imperative sentences ending in a period, e.g. `Persist path must be absolute: '/relative/path'.`).

This slice does NOT touch the runtime tool — that's slices 4 and 5. It also does NOT introduce per-directory exclusions (out of scope for v1 per the PRD).

## Acceptance criteria

- [ ] Host Config and Host Core accept a `persist: { directories: [], files: [] }` object
- [ ] `persist` is deep-merged across Host Core and Host Config (host-specific paths are added to core-declared paths, not replacing them)
- [ ] All validation rules from the PRD's table are implemented with the exact messages specified, matching the existing short-imperative style
- [ ] Errors abort the install; warnings print and continue
- [ ] Extension Persist Mount units land under `/persist/etc/systemd/system/` (not `/usr/lib/`)
- [ ] Extension tmpfiles entries land under `/persist/etc/tmpfiles.d/`
- [ ] Each declared extension path is moved from its live location to the Persist Dataset before `@blank` is taken
- [ ] After install, `systemctl list-units 'persist-*.mount'` includes both curated defaults (from `/usr/lib/`) and declared extensions (from `/persist/`)
- [ ] When `options.impermanence.enabled=false`, declaring `persist` paths in host config produces only the warning — no datasets, units, or moves happen
- [ ] `tests/chroot-impermanence.bats` covers extension unit generation, deep-merge, validation rules (error and warning paths), and the move semantics for extensions

## Blocked by

- `.scratch/impermanence/issues/01-core-impermanence.md`
