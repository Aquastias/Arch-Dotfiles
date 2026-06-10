# Migrate remaining hosts + all users to profile.jsonc

Status: ready-for-human

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Migrate every remaining host and user to a unified `profile.jsonc`. Each
host (`core`, `desktop`, `laptop`, `vm/arch-hyprland`, `vm/arch-kde`,
`vm/arch-kde-hyprland`, `vm/arch-secure`) gets a `profile.jsonc` merging
its former `install.template.jsonc` + `config.jsonc`. Each user (`core`,
`aquastias`, `vm-data`, `vm-test`) `config.jsonc` becomes `profile.jsonc`.
The equivalence test from the tracer guards each host so every commit
stays green. Test fixtures and VM test profiles move to the new shape.

## Acceptance criteria

- [x] Every remaining host gets a `profile.jsonc` merging its former
      template + config.
- [x] Every user `config.jsonc` becomes `profile.jsonc` (+
      `users/core/profile.jsonc`).
- [x] Equivalence test green for each migrated host.
- [x] Test fixtures + VM test profiles updated to the `profile.jsonc`
      shape; all suites green.

## Blocked by

- `.scratch/unified-host-profile/issues/08-migration-tracer-arch-data.md`
- `.scratch/unified-host-profile/issues/03-install-profile-frontend.md`
- `.scratch/unified-host-profile/issues/04-locale-keymap-arrays.md`
- `.scratch/unified-host-profile/issues/05-ssh-toggle.md`
- `.scratch/unified-host-profile/issues/06-runner-reconciliation-user-services.md`

## Comments

### Agent — migration complete (TDD), all green

Additive migration (new `profile.jsonc` coexists with legacy
`config.jsonc`/`install.template.jsonc`; legacy removed in issue 10).
Guard `tests/config/profile-migration.bats` (deleted in issue 10):
per-host = software byte-equal (`_load_profile_synthesize` vs
`load_profile` over `{users,system_programs,sysctl,packages,persist,
post_install}`) + device-free skeleton + closed-schema clean; per-user =
`load_user_config` vs `load_user_profile` full-equal.

Two commits:
- `feat(host-profile): Migrate desktop + aquastias to profile.jsonc`
- `feat(host-profile): Migrate remaining hosts, users, fixtures to
  profile.jsonc`

Hosts: desktop (multi: rpool mirror + dpool raidz1 `data` group → /data,
ashift 12), arch-kde/-hyprland/-kde-hyprland (single), arch-secure (multi
mirror + sops/impermanence/encryption), laptop (single). Users: aquastias,
vm-data, vm-test (+ users/core). Fixtures: host-a/host-b/core.

Decisions (operator-confirmed): desktop+laptop DE = `["kde","hyprland"]`;
desktop 2×NVMe rpool mirror + 3×SSD dpool raidz1; ashift 12 uniform. Suite
942 ok / 0 fail (non-VM); VM profile-resolution tests green.

**Human check before issue 10:** a real/VM install of `--profile desktop`
(or a vm smoke) to confirm the authored disk skeleton + DE are right, since
issue 10 deletes the legacy files + equivalence guard.
