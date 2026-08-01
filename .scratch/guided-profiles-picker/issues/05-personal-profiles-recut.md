# Personal profiles re-cut (desktop + laptop)

Status: done

## Parent

.scratch/guided-profiles-picker/PRD.md
ADR: docs/adr/0055-guided-profiles-picker-and-default-secret-posture.md

## What to build

Re-cut the two personal Host Profiles to their real shape: encrypted, impermanent,
SSH-enabled ZFS machines. In both `hosts/desktop/profile.jsonc` and
`hosts/laptop/profile.jsonc`:

- Add explicit `filesystem: "zfs"` (on the profile's face, not an inherited seed
  default).
- `options.encryption` on.
- `options.impermanence.enabled` on (dataset/mount defaults `rpool/persist` →
  `/persist`; validation requires the persist dataset on the OS pool — `rpool`
  satisfies both).
- `options.ssh.enabled` on.
- `persist.directories` = `/home`, `/var/lib/docker`, `/var/lib/libvirt`
  (additive over the `impermanence-common.sh` base set; both profiles install
  docker + virt-manager).

Layouts are already correct and stay unchanged (desktop `mode: multi`, `rpool`
mirror ×2 + `data` raidz1 ×3; laptop `mode: single`).

## Acceptance criteria

- [ ] Both profiles declare `filesystem: "zfs"` explicitly
- [ ] Both have `options.encryption`, `options.impermanence.enabled`,
      `options.ssh.enabled` on
- [ ] Both persist `/home`, `/var/lib/docker`, `/var/lib/libvirt`
- [ ] Existing layouts are unchanged
- [ ] Each profile loads and validates clean against the closed schema (ADR 0036),
      including the impermanence same-pool rule
- [ ] Covered by a profile-load / validation assertion (existing validation-test
      prior art)

## Blocked by

- None — can start immediately.
