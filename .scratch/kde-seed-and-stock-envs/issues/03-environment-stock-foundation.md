# 03 — `environment.stock` foundation

**What to build:** The [[Environment Config]] accepts a new `stock` bool (default
`false`) that a Host Profile or the Guided Installer can set. It validates
against the closed schema, resolves at config-load like `wayland_shell`, and
threads into the chroot as `ENVIRONMENT_STOCK` so the [[Desktop Environment
Adapter]]s can later read it. No adapter consumes it yet — this is the config
path only. (ADR 0112 core.)

**Blocked by:** None — can start immediately.

**Status:** done

- [x] `environment.stock` (bool, default `false`) is added to the closed schema;
      an unknown/malformed value aborts at load with an actionable message.
- [x] `lib/config/environment.sh` resolves `stock` into a resolved global and
      exports `ENVIRONMENT_STOCK` into the chroot, mirroring
      `ENVIRONMENT_WAYLAND_SHELL`.
- [x] `tests/config/environment-resolution.bats` and
      `environment-validation.bats` assert: default false, valid bool resolves
      and threads, invalid value aborts (mirror the `wayland_shell` cases).
- [x] The `stock` vs explicit `wayland_shell: noctalia` contradiction is
      resolved with `stock` authoritative for the selected desktops, documented
      at the validation site (compact comment).
- [x] Existing test suite stays green.

## Comments

- 2026-09-27 doc sync: shipped in 6dfb331, 3918ff4, b34e8da, 11d0e5c, 96de292,
  577586f (ADR 0111-0115).
