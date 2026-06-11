# Migration tracer: equivalence test + migrate arch-data

Status: done

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Prove the whole migration path on the smallest host. Add an equivalence
test asserting that the legacy synthesis (template + config through the
assembler) produces the same effective config as a hand-written
`profile.jsonc` for a given host. Then migrate `arch-data` first — the
template-less VM host — by writing `hosts/vm/arch-data/profile.jsonc` and
removing its `config.jsonc`. This is the tracer that de-risks the bulk
migration.

## Acceptance criteria

- [x] An equivalence test asserts legacy synthesis == hand-written
      `profile.jsonc` for a host.
- [x] `hosts/vm/arch-data/profile.jsonc` replaces its `config.jsonc`.
- [x] `arch-data` installs via `--profile arch-data` (or a VM run).
- [x] Equivalence test green for `arch-data`; all suites green.

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`

## Comments

### Agent (TDD)

Design B: a complete `profile.jsonc` (machine skeleton minus devices +
software), so the profile fully describes the machine.

- `hosts/core/profile.jsonc` mirrors the core software base; coexists
  with the legacy core files during migration (both produce the same
  base).
- `hosts/vm/arch-data/profile.jsonc` carries system/options + the pool
  skeleton (os_pool topology none; data_pools tank0 stripe / tank1
  mirror) with no device fields; `config.jsonc` removed.
- `load_profile` gained the `hosts/vm/<name>/` real-path fallback
  (mirrors `_configs_load`), so VM hosts resolve their `profile.jsonc`.
- Equivalence guard (`tests/config/profile-loader.bats`): `load_profile
  arch-data` preserves the legacy software synthesis ({sysctl,
  system_programs:[cups], users:[vm-data]}) and adds the skeleton; no
  `host_profile`; validates closed-schema. Plus a VM real-merge unit.

Full suite green (1038/1038). `--profile arch-data --print-config`
emits the correct skeleton.

AC3 (actual install) is the VM gate: arch-data's data pools need
per-group disk assignment, which the interactive picker defers to the
VM harness rewire (issue 07). Hence `ready-for-human`.

### Agent verification (Claude) — 2026-06-10

AC3 is **still blocked**, but I fixed one real bug and pinned a second
gap that must be closed before arch-data can install via `--profile`.

**Bug fixed — Runner/pool-owners read the legacy `config.jsonc`.** The
front-end (issue 03) assembles a correct effective config (arch-data →
`users:["vm-data"]`, tank0/tank1), but the **Profiles Runner**
(`lib/profiles/runner.sh`) and **pool-owners** (`lib/zfs/pool-owners.sh`)
re-read `load_host_config $RESOLVED_HOST_PROFILE` (legacy `config.jsonc`).
arch-data has no `config.jsonc` (removed here) → `load_host_config` returns
`rc=1` → the Runner *skips entirely* (no `vm-data`, pools left root-owned),
and pool-owners trips the ERR trap (the spurious "failed at line 290"). It
only "works" for other hosts because their `config.jsonc` still exists
(issue 10 would break them all). Fix: both now read the effective
`$CONFIG_FILE` (the single source of truth). bats green (1048). This is a
prerequisite for issue 10's "remove legacy readers".

**Gap #5 (still open) — per-group data-pool disk assignment.** Neither the
interactive picker (`_install_pick_assignment`) nor the VM harness
(`_profile_resolve_host`) distributes picked disks across `os_pool` +
`storage_groups` + `data_pools`; they fill only `os_pool`. So
`host_profile: arch-data` can't assemble (tank0/tank1 get 0 disks). Worse,
`picker_assign_disks` validates via `picker_validate_layout`
(`none`/`stripe` ≥2), which **conflicts** with `layout_validate`
(`none`=1, `stripe`=1) that arch-data relies on — reconciling them risks
the interactive picker's own tests. This is issue 03's explicitly-deferred
follow-up and warrants its own issue, not an inline hack. Until then,
arch-data installs only via an **inline** install config (the data-pools
VM tests prove the topology end-to-end).

### AC3 closed — gap #5 done (issue 12), live VM verified — 2026-06-11

Both blockers above are resolved. Gap #5 shipped as **issue 12** (ADR 0037,
per-group `disk_count` slicing), and the Runner/pool-owners legacy-reader
fix is in. AC3 verified on the live VM via the new top-level-`host_profile`
profile `tests/vm/profiles/data-pools/from-profile.jsonc`:
`vm.sh --testing --verify-boot --recreate --profile data-pools/from-profile`
→ slicer mapped rpool→sda2 / tank0→sdb1 / tank1→mirror(sdc1,sdd1);
`INSTALLER-EXIT-0`; pool verifier `===FIRSTBOOT-OK===` (rpool/tank0/tank1
imported, /data/tank0 + /data/tank1 mounted + owned by `vm-data`, by-id
vdevs). Closing this issue. See issue 12 for the full record.
