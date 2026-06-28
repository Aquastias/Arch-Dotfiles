# 04 — LUKS encryption for non-ZFS roots

Status: done (install VM-verified; encrypted boot is HITL)
Type: AFK

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Layer LUKS encryption onto the non-ZFS root path from issue 03. Reuse the
existing passphrase seam verbatim (`collect_enc_passphrase` / `prompt_secret` /
the `INSTALL_ENC_PASSPHRASE` VM seam) — only the consumer differs: pipe the same
secret to `cryptsetup luksFormat`/`luksOpen` instead of `zpool create`. The Root
Adapter's `ROOT_CMDLINE` becomes `root=/dev/mapper/cryptroot` with
`cryptdevice=UUID=…:cryptroot`, and its `HOOKS` gain `encrypt` before
`filesystems`. The swap partition is LUKS-wrapped when the root is encrypted.

## Progress

Pure cores landed + bats-green (TDD), VM-gated wiring still to do:
- [x] **Encrypted ext4 `ROOT_CMDLINE`/`HOOKS`** — `ext4_root_cmdline <uuid>
      encrypted` → `cryptdevice=UUID=…:cryptroot root=/dev/mapper/cryptroot`;
      `ext4_hooks encrypted` inserts `encrypt` between `block` and `filesystems`
      (`tests/layout/ext4-boot.bats`).
- [x] **Plan owns partition slots** — `nonzfs_partition_plan` emits
      `esp/swap/root_part_num` (swap empty + root→2 when no swap); the planner is
      the single numbering authority (`tests/layout/nonzfs-plan.bats`).
- [x] **Non-ZFS LUKS device resolver** (`lib/layout/nonzfs/devices.sh`) — reads
      the plan's slots (no re-derivation) and maps them to devices; encrypted →
      `/dev/mapper/cryptroot` + `cryptswap` and a `luks_containers`
      `<part>:<mapper>` list; plaintext → bare partitions
      (`tests/layout/nonzfs-devices.bats`).
- [x] **ext4 Root Adapter LUKS path** (`lib/layout/ext4/single.sh`,
      `_ext4_luks_open_root`) — pipes `ZFS_PASSPHRASE` (the shared seam) to
      `cryptsetup luksFormat`/`open` for the root; mkfs.ext4 on
      `/dev/mapper/cryptroot`; encrypted cmdline/HOOKS selected by
      `_ext4_enc_mode`. cryptsetup added to the package list for a non-ZFS
      encrypted root (`lib/packages/list.sh`).
- [x] **Encrypted swap** — random-key dm-crypt via `/etc/crypttab` (re-keyed each
      boot; hibernate out of scope) written by `write_crypttab`
      (`lib/chroot.sh`, `LAYOUT_CRYPTTAB`); fstab points at `/dev/mapper/
      cryptswap`. (Deviation from a LUKS+keyfile swap — random-key avoids
      keyfile-before-pacstrap ordering and matches the no-hibernate scope.)

VM-verified 2026-06-28: encrypted ext4 **install** reaches `INSTALLER-EXIT-0`
(LUKS root format/open, cryptsetup, `[encrypt]` hook, crypttab written,
`cryptdevice=…` boot entry). Commit slice 3 `569ec09`. Also fixed a gating gap
the bootstrap-skip exposed: the ZFS hostid/zpool.cache/pacman.conf seed +
finalize export are now gated on `command -v zpool` (`lib/chroot.sh`,
`lib/finalize.sh`) — a non-ZFS root has none of them. New profile
`tests/vm/profiles/single/ext4-encrypted.jsonc`.

## Acceptance criteria

- [~] An encrypted ext4 root prompts once for the passphrase in initramfs and
      boots — **install VM-verified; the boot passphrase test is HITL** (boot the
      installed disk, type `testtest`). Encrypted roots can't headless
      boot-verify.
- [x] The same passphrase seam is used as ZFS (`ZFS_PASSPHRASE` /
      `collect_enc_passphrase`); the `INSTALL_ENC_PASSPHRASE` VM preset works.
- [x] `ROOT_CMDLINE` emits `cryptdevice=…:cryptroot` + `root=/dev/mapper/
      cryptroot`; `HOOKS` include `encrypt` before `filesystems` (`[encrypt]`
      build hook observed in the VM).
- [x] Swap is encrypted when the root is encrypted (random-key crypttab),
      plaintext partition when not.
- [x] bats covers the encrypted-variant `ROOT_CMDLINE`/`HOOKS` emitters and the
      partition/LUKS device resolver with the encrypt flag set.

## Blocked by

- `03` (ext4 plaintext root tracer)
