Status: ready-for-agent

# Install Config Reader module + one consumer migrated (tracer)

## Parent

`.scratch/config-modules-refactor/PRD.md`

## What to build

Create `lib/install-config.sh`. Implement typed `install_config_*`
accessors for the `options.*` namespace — at minimum:

- `install_config_kernel` (default `lts`)
- `install_config_bootloader` (default `systemd-boot`)
- `install_config_swap_enabled` (default `true`)
- `install_config_esp_size` (default `512M`)
- `install_config_impermanence_enabled` (default `false`)
- `install_config_impermanence_dataset` (default `rpool/persist`)
- `install_config_impermanence_mount` (default `/persist`)
- `install_config_age_key_url` (no default — empty when absent)

Each accessor wraps `cfgo` and applies the canonical default.
`install-config.sh` is the sole module that owns these defaults.

Migrate one consumer end-to-end as the tracer:
`lib/chroot.sh::configure_system` — replace the inline `cfgo +
${X:-default}` patterns for kernel, bootloader, swap, impermanence
dataset/mount with the new accessors.

The rest of the consumers stay on the old pattern for now (covered by
slice 02).

## Acceptance criteria

- [ ] `lib/install-config.sh` exists and is sourced by `03-install.sh`
      (alongside other modules)
- [ ] All accessors listed above are implemented
- [ ] Bats test file `tests/install-config.bats` covers each accessor
      with two cases: field-present and field-absent (default applied)
- [ ] `lib/chroot.sh::configure_system` no longer contains
      `${X:-default}` fallbacks for the options namespace; it calls
      `install_config_*` accessors instead
- [ ] `tests/chroot-configure.bats` passes unmodified
      (behavior-preserving)
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

None - can start immediately.
