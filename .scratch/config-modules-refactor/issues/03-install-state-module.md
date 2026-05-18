Status: ready-for-agent

# Install State module + replace `load-state.sh` + remove dead defaults

## Parent

`.scratch/config-modules-refactor/PRD.md`

## What to build

Create `lib/install-state.sh` owning the host↔chroot wire format
(`/root/lib-chroot/install-state.json`).

Public interface:

- `install_state_write <path>` — host side. Reads from
  `install_config_*` accessors and other resolved globals
  (`RESOLVED_HOSTNAME`, `LAYOUT_OS_POOL_NAME`, `LAYOUT_ESP_PARTS`,
  `ENVIRONMENT_DESKTOP`, persist sub-object derived from merged host
  config) and writes the JSON document.
- `install_state_load <path>` — chroot side. Replaces today's
  `lib/chroot/load-state.sh`. Exports every state field as a shell
  variable. No JSON-level defaults — every field must be present in
  the wire format.
- `install_state_update <path> <key> <value>` (or equivalent
  field-update primitive) — used by `lib/secrets.sh` to splice in
  tmpfs paths without rewriting the whole file.

Declare the field list in one place; both `install_state_write` and
`install_state_load` iterate it (or a shared schema construct).

Migration:

- `lib/chroot.sh::configure_system` calls `install_state_write`
  instead of the inline `jq -n --arg ...` block.
- `lib/chroot/configure.sh` and every chroot sub-script source
  `install_state_load` (replacing `load-state.sh`).
- `lib/chroot/load-state.sh` is deleted.
- `lib/secrets.sh::_secrets_write_state` uses `install_state_update`
  for both host and per-user paths.
- The defensive `// "default"` JSON fallbacks in the former
  `load-state.sh` are removed; missing fields are an error.

## Acceptance criteria

- [ ] `lib/install-state.sh` exists with `install_state_write`,
      `install_state_load`, and a field-update primitive
- [ ] `lib/chroot/load-state.sh` is deleted; every consumer points at
      `install_state_load`
- [ ] `lib/chroot.sh::configure_system` no longer contains the
      inline `jq -n --arg ...` state-write block
- [ ] `lib/secrets.sh::_secrets_write_state` uses the new field-update
      primitive (no hand-rolled `jq` mutation)
- [ ] No JSON-level defaults (`// "..."`) remain in chroot-side state
      reads
- [ ] Round-trip bats test in `tests/install-state.bats` builds a
      fake state via the writer, loads it via the reader, asserts
      every field comes back intact
- [ ] A "missing field is an error" test in `tests/install-state.bats`
- [ ] `tests/chroot-load-state.bats` is updated (or replaced) to
      exercise `install_state_load`; passes
- [ ] `tests/chroot-configure.bats`,
      `tests/chroot-install-state-persist.bats`,
      `tests/profiles-secrets.bats` pass unmodified
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

- `.scratch/config-modules-refactor/issues/01-install-config-reader-tracer.md`
