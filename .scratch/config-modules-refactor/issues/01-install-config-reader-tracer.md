Status: done

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

- [x] `lib/install-config.sh` exists and is sourced by `03-install.sh`
      (alongside other modules)
- [x] All accessors listed above are implemented
- [x] Bats test file `tests/install-config.bats` covers each accessor
      with two cases: field-present and field-absent (default applied)
- [x] `lib/chroot.sh::configure_system` no longer contains
      `${X:-default}` fallbacks for the options namespace; it calls
      `install_config_*` accessors instead
- [ ] `tests/chroot-configure.bats` passes unmodified
      (behavior-preserving)
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

None - can start immediately.

## Comments

- 2026-09-27 audit: 7e16f76 (lib/install-config.sh + install-config.bats).
  Later: the install config later became the schema-driven accessor table (ADR
  0015, 6145524) and the unified Host Profile (ADR 0036). Remaining unticked
  lines are suite/VM runs not re-verifiable now.
