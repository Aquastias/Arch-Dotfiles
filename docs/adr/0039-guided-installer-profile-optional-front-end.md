# Guided Installer as a third, profile-optional front-end

The Single Entry Point gains a third front-end — the **Guided Installer**, an
interactive fzf menu launched by bare `install.sh` — that builds an Effective
Config from scratch (merged over Host Core) when no Host Profile exists yet. It
can **Proceed** (install from a tmpfs Effective Config), **Save Profile** (commit
a device-less `hosts/<name>/profile.jsonc`), or **Export Effective Config** (write
a device-baked file to an operator path *outside* the repo's `hosts/` tree).

This **amends ADR 0036**: an install may now originate from no committed
artifact, so 0036's committed-source-of-truth guarantee is *scoped* to the
profile path — guided is the explicitly un-audited on-ramp, with Save as the
bridge back to a committed profile.

## Considered Options

- **(a)** Ephemeral-only third front-end.
- **(b)** Ephemeral + optional Save to profile/config — **chosen**.
- **(c)** Require loading a profile first — rejected; defeats the purpose
  (you can already tweak a profile via `--profile`).

## Consequences

- Device paths are never committed: Save strips disks (keeps the
  mode/topology/`disk_count` skeleton); only Export carries devices, and only
  outside `hosts/`.
- Bare `install.sh` now launches the Guided Installer, replacing the retired
  `generate_template` "write a stub, hand-edit, re-run" path. The VM seed must
  pass its Effective Config **positionally** (`install.sh <path>`) instead of
  relying on the bare-default `install.jsonc`.
- New host-schema fields: `options.mirror_countries[]` (default
  Germany/Switzerland/Sweden/France/Romania, fed to `reflector --country`) and
  `options.multilib` (bool, default true; makes the existing always-on
  `enable_multilib` honour a flag). `testing` repos are deliberately **not**
  offered — they pull kernels newer than archzfs tracks and break the ZFS DKMS
  build (ADR 0023/0024).
- Save refuses to overwrite an existing committed `hosts/<name>/` or
  `users/<name>/` profile — it always demands a new name.
- The pure config-assembly + menu-model core lives in `lib/guided/` and is
  bats-tested (state → emitted JSON); the thin fzf/TTY shell is smoke-only;
  installation itself reuses the existing back-end + VM coverage. Topology rules
  are reused from `lib/layout/multi.sh`'s pure `suggest_*_topologies` and
  `lib/picker.sh`'s `picker_validate_layout`, not re-derived.
