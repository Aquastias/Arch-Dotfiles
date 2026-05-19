Status: done

# Migrate remaining Install Config consumers

## Parent

`.scratch/config-modules-refactor/PRD.md`

## What to build

Extend `lib/install-config.sh` with accessors for the remaining
namespaces touched by current default-fallback sites:

- `system.*` — `install_config_hostname`, `install_config_locale`,
  `install_config_timezone`, `install_config_keymap` (default `us`)
- `environment.*` — `install_config_desktop` (array),
  `install_config_gpu` (array)
- `post_install.*` — `install_config_extras_backup` (default `false`),
  `install_config_extras_security` (default `false`)
- `packages.*` — `install_config_packages_extra`,
  `install_config_packages_groups`
- `dotfiles_repo` (top-level)

`packages.repo` and `packages.aur` are Host Config fields (read from
`.os/hosts/<hostname>/config.jsonc`, not `CONFIG_FILE`) and belong to
a future Host Config Reader — out of scope for this issue.

Migrate every remaining consumer that today reads a default-bearing
field via `cfgo + ${X:-default}`:

- `lib/packages.sh` (kernel, bootloader, packages)
- `lib/environment.sh` (already does its own resolution — migrate the
  raw-field reads)
- `lib/validation.sh` (impermanence dataset/mount, persist, environment)
- `lib/config.sh::print_summary` (every default fallback in the summary)
- `lib/layout-common.sh` (`esp_size`)
- `lib/layout-single.sh` and `lib/layout-multi.sh` (their own field
  reads)
- `lib/profiles.sh` (`dotfiles_repo`)

After this slice, no module outside `install-config.sh` should contain
a default-fallback for any Install Config field. `cfg` / `cfgo` calls
without an inline default are still allowed where the value is purely
informational (e.g. diagnostics, summary).

## Acceptance criteria

- [ ] All accessors listed above are implemented and tested in
      `tests/install-config.bats`
- [ ] `grep -rn "cfgo.*}.*:-" .os/lib/ .os/tools/` returns no hits
      outside `lib/install-config.sh`
- [ ] All listed consumer modules are migrated
- [ ] Existing bats suite passes unmodified
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

- `.scratch/config-modules-refactor/issues/01-install-config-reader-tracer.md`
