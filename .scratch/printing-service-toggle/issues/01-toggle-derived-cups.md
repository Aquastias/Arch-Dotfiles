# 01 — Toggle-derived cups (core mechanism, default-on preserved)

**What to build:** Make whether `cups` lands on a host depend on a single
switch, `options.printing.enabled` (default **on**), instead of an unconditional
Host Core entry. A default install still installs cups and enables
`cups.service` exactly as today — but now because the toggle defaults on. A
profile (or guided session) with `options.printing.enabled: false` produces a
machine with **no** cups at all. cups stays a real root/chroot System Program
(its Program directory, `config.jsonc`, and `install.sh` are unchanged); only
*what puts it on the system-programs list* changes.

This slice is deliberately atomic: `cups` is removed from Host Core **and** the
toggle-driven injection is added in the same slice, because removing it from core
without the injection would stop cups installing on a default host (breaking the
default-installs-cups invariant). Both land together to keep CI green.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [x] `options.printing.enabled` is accepted by the closed profile schema; an
      unknown neighbour key still aborts at load with its path.
- [x] A config accessor resolves the toggle with default `true`; the guided seed
      baseline defaults printing on.
- [x] Config State normalises the field out when equal to the default (on), so
      only opting out persists a value / `●` override.
- [x] A single pure function (mirroring `post_install_programs`) is the sole
      source of truth: given a config it emits `cups` when the toggle is on and
      nothing when off; an unset toggle is treated as on.
- [x] Effective-Config assembly (the `--profile` assembly and the guided emit
      path) injects `cups` into `system_programs` iff the pure function produces
      it; the Runner then installs it in the chroot as an authored System Program
      would, and `cups.service` is enabled by its own `install.sh`.
- [x] `cups` is removed from Host Core `system_programs`; a default host still
      installs cups, and a `printing.enabled: false` profile installs none.
- [x] The unattended `install.sh <config-file>` path (pre-assembled config) is
      unaffected — its `system_programs` already reflects the authoring
      front-end's toggle.
- [x] Tests: a new pure-function bats spec (mirroring `config/post-install.bats`)
      covers on/off/unset; assembly bats assert cups presence/absence by toggle;
      schema-loader bats assert the key loads and typos still abort.
