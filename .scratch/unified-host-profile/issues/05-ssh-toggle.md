# ssh toggle

Status: ready-for-agent

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Add `options.ssh.enabled` (default false). When true, enable
`sshd.service` in the chroot; `openssh` is already pacstrapped via the
Base Package List, so this only flips the service. Closes the gap where
`openssh` is installed today but never enabled.

## Acceptance criteria

- [ ] Schema accepts `options.ssh.enabled` (default false).
- [ ] When true, `sshd.service` is enabled in the chroot.
- [ ] When false/absent, `sshd` is not enabled (status quo).
- [ ] bats: schema default + the enable path covered.

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`
