# ssh toggle

Status: done

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Add `options.ssh.enabled` (default false). When true, enable
`sshd.service` in the chroot; `openssh` is already pacstrapped via the
Base Package List, so this only flips the service. Closes the gap where
`openssh` is installed today but never enabled.

## Acceptance criteria

- [x] Schema accepts `options.ssh.enabled` (default false).
- [x] When true, `sshd.service` is enabled in the chroot.
- [x] When false/absent, `sshd` is not enabled (status quo).
- [x] bats: schema default + the enable path covered.

## Comments

Threaded through every layer via TDD: closed schema accepts
`options.ssh.enabled`; accessor `install_config_ssh_enabled` (bool, default
false); install-state carries `SSH_ENABLED`; `enable_optional_services`
(new, beside `enable_base_services`) enables `sshd.service` only when true,
wired into `configure.sh`. Fully unit-tested (no VM-only carve-out).

Tests: +1 profile-loader, +2 install-config, +3 install-state, +3
chroot-configure; install-state fixtures updated for the new wire field.
Full suite green (1021).

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`
