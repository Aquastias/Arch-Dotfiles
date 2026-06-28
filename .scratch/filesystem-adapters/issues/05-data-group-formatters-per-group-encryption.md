# 05 — Data Group Formatters (ext4/xfs/btrfs) + per-group encryption

Status: done
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

- [x] A ZFS root + ext4 data group installs; the ext4 disk mounts at its declared
      mount on boot. (ext4 data path VM-verified; profiles 0c92f96/96ae769)
- [x] xfs and btrfs data groups format and mount; btrfs data groups honor native
      topology (raid0/1/10). (**VM-verified 2026-06-29**: `data-pools/xfs` →
      `/data/tank0` xfs mounts at boot; `data-pools/btrfs` raid1 over 2 disks
      `Found device … btrfs tank0` → `Mounted /data/tank0`, FIRSTBOOT-OK)
- [x] A plaintext data group next to an encrypted root works, and an encrypted
      data group next to a plaintext root works (per-group flag is independent).
      (per-group `enc` honored for zfs pools too via `zfs_data_pool_enc_opts`)
- [x] An encrypted data group auto-unlocks post-boot from the keyfile-on-root via
      generated crypttab / zfs key-load — no second passphrase prompt.
      (**VM-verified 2026-06-29** `data-pools/zfs-enc`: boot log `Starting Load
      ZFS encryption key for tank0…` → `Finished` → `tank0/data` mounted,
      FIRSTBOOT-OK, fully headless = no prompt. LUKS crypttab path: ext4-enc
      VM-verified earlier.)
- [x] When root impermanence is on, the data-group keyfile is placed in a
      persisted / never-rolled-back path. (`/etc/cryptsetup-keys.d` curated, 146d3ae)
- [x] bats covers the crypttab / zfs-key-load emitter (per-group encryption →
      expected crypttab text + keyfile placement path; `false` round-trips).
      (`tests/layout/datacrypt.bats`; `tests/layout/zfs-datakey.bats`;
      `_enc_opts_prompt` in `tests/zfs/zfs-pools.bats`)

## Blocked by

- `02` (dispatch split), `04` (LUKS plumbing)

## Comments

### zfs data-keyload finish (TDD) — 2026-06-29

Closed the last code gap: an encrypted **Standalone ZFS Data Pool** now
auto-loads its key post-boot from a keyfile on the root, instead of riding the
root's `keylocation=prompt` (which re-prompted / coupled to the root secret).

Pure cores, TDD'd first (bats):
- `lib/layout/zfs/datakey.sh::zfs_data_pool_enc_opts <enc> <name>` — projects the
  shared `data_group_crypto` zfs plan into `(keyfile, opts)`; plaintext → empty.
- `lib/zfs/pools.sh::_enc_opts_prompt <opts…>` — true iff opts use
  `keylocation=prompt`. `_zpool_create` now pipes the boot passphrase only then,
  so a keyfile-on-root pool never re-prompts. rpool/dpool behavior unchanged.

VM-gated wiring:
- `create_data_pools` selects per-pool opts (independent of root), generates the
  32-byte raw key to **both** `${MOUNT_ROOT}<keyfile>` (persisted) and the live
  `<keyfile>` path so `zpool create` reads it whether `keylocation=file://` is
  resolved against the `-R` altroot or live `/` (the open altroot question).

Per-group independence: dropped the global `build_enc_opts` reliance for
standalone pools — `enc=false` is now genuinely plaintext next to an encrypted
root (was wrongly inheriting the machine prompt opts).

1514 bats, 0 fail. Shellcheck: no new warnings.

### VM verification — 2026-06-29 (issue CLOSED)

Ran all three smokes headless (`vm.sh --testing --verify-boot`); the encrypted
ZFS data pool next to a **plaintext** zfs root is headless-verifiable (root boots
with no prompt, data auto-loads from its keyfile). The smokes surfaced four real
gaps the bats cores couldn't — each fixed test-first:

1. **Boot-time zfs key-load missing.** `create_data_pools` wrote the keyfile +
   created the pool headlessly, but nothing loaded the key at boot → `tank0/data`
   NOT MOUNTED. Upstream OpenZFS ships no `zfs-load-key@.service`; the existing
   `configure.sh` enable silently no-op'd. Fix: ship the template
   (`zfs_write_load_key_template`, `lib/chroot/zfs-import.sh`), enable it only for
   **file-keyed** pools (not the prompt-keyed root), skip them from the
   zfs-mount-generator cache. → boot log `Load ZFS encryption key for tank0` +
   `tank0/data` mounted, FIRSTBOOT-OK.
2. **xfs/btrfs not mountable on the live ISO.** mkfs succeeded but the fs kernel
   module wasn't loaded → `mount` failed. Fix: `modprobe "$fs"` before mount in
   `data_group_create`; add `xfsprogs`/`btrfs-progs` to the target
   (`install_config_uses_filesystem` + `packages/list.sh`) for boot fsck.
3. **Stale non-zfs data mount failed the pool export** → rpool left active →
   initramfs panic next boot ("previously in use from another system"). Fix:
   `finalize` unmounts non-zfs mounts under `${MOUNT_ROOT}` (deepest-first) before
   `zpool export` (`_finalize_nonzfs_mounts`). [the memory-flagged follow-up]
4. **btrfs `raid1` rejected as "unknown topology"** by two zfs-only validators.
   Fix: `_picker_group_min` learns btrfs raid profiles; layout validation
   dispatches per-fs (`_data_pool_topology_ok`).

Results: `zfs-enc` (encrypted zfs data, keyfile auto-load, no prompt), `xfs`,
`btrfs raid1` (2-disk native topology) — all INSTALLER-EXIT-0 + FIRSTBOOT-OK.
1529 bats, 0 fail; shellcheck no new warnings. Benign: a pre-existing
`zfs-mount-generator exit 1` line for rpool (cosmetic — all datasets still mount
via zfs-mount.service; present on earlier verified runs too).
