# Migrate remaining hosts + all users to profile.jsonc

Status: ready-for-agent

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

- [ ] Every remaining host gets a `profile.jsonc` merging its former
      template + config.
- [ ] Every user `config.jsonc` becomes `profile.jsonc` (+
      `users/core/profile.jsonc`).
- [ ] Equivalence test green for each migrated host.
- [ ] Test fixtures + VM test profiles updated to the `profile.jsonc`
      shape; all suites green.

## Blocked by

- `.scratch/unified-host-profile/issues/08-migration-tracer-arch-data.md`
- `.scratch/unified-host-profile/issues/03-install-profile-frontend.md`
- `.scratch/unified-host-profile/issues/04-locale-keymap-arrays.md`
- `.scratch/unified-host-profile/issues/05-ssh-toggle.md`
- `.scratch/unified-host-profile/issues/06-runner-reconciliation-user-services.md`
