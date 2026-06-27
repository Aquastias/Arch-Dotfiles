# 05 — Data Group Formatters (ext4/xfs/btrfs) + per-group encryption

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Let a data group be formatted with its own filesystem, independently of the root
— the original "ZFS root + ext4 data disk" ask, plus xfs/btrfs data groups. Build
the ext4/xfs/btrfs Data Group Formatters dispatched per group via
`data_formatter_source`. Add per-group encryption: an encrypted data group is
auto-unlocked **post-boot** by a keyfile stored on the (already-unlocked)
encrypted root, wired via a generated `crypttab` / `zfs` key-load. Under
impermanence the keyfile must live in the curated persist set / a
never-rolled-back path so it survives reboot.

## Acceptance criteria

- [ ] A ZFS root + ext4 data group installs; the ext4 disk mounts at its declared
      mount on boot.
- [ ] xfs and btrfs data groups format and mount; btrfs data groups honor native
      topology (raid0/1/10).
- [ ] A plaintext data group next to an encrypted root works, and an encrypted
      data group next to a plaintext root works (per-group flag is independent).
- [ ] An encrypted data group auto-unlocks post-boot from the keyfile-on-root via
      generated crypttab / zfs key-load — no second passphrase prompt.
- [ ] When root impermanence is on, the data-group keyfile is placed in a
      persisted / never-rolled-back path.
- [ ] bats covers the crypttab / zfs-key-load emitter (per-group encryption →
      expected crypttab text + keyfile placement path; `false` round-trips).

## Blocked by

- `02` (dispatch split), `04` (LUKS plumbing)
