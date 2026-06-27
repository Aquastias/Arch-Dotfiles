# Per-group filesystem & layout-adapter decomposition

Extends ADR 0040. The installer gains real btrfs/ext4/xfs support, and the
`filesystem` choice becomes **per group**: the top-level `filesystem` names the
OS/root filesystem (keeping its existing role as the driver of
`encryption_method` and impermanence eligibility), while each data group may
carry an *optional* `filesystem` that defaults to the root value. One machine can
therefore mix filesystems by group — e.g. a ZFS root with an ext4 data disk.

## Considered Options

- **(a)** Keep `filesystem` install-wide (one FS per machine) — rejected; the
  whole point is "select per disk/group."
- **(b)** Top-level `filesystem` = root FS + optional per-data-group override —
  **chosen**. Additive (ADR 0040's promise): the risky boot-coupled root path
  never consults a group field; data groups gain one optional field.
- **(c)** Remove the top-level discriminator, every group (incl. OS) self-
  describes — rejected; relocates the discriminator and breaks the closed-schema
  accessors + validation + VM-seed lockstep ADR 0040 flagged as the costly part.

## Decisions

- **Multi-disk story is FS-native, no mdadm/LVM.** ZFS (mirror/raidz) and btrfs
  (raid0/1/10) own topology natively. ext4 and xfs are **single-disk only** — a
  group set to ext4/xfs rejects `disk_count > 1`. Redundancy on a non-ZFS/btrfs
  group is simply not offered (use ZFS or btrfs). This avoids a whole RAID/volume-
  manager axis.
- **Encryption seam shared, consumer FS-conditional.** The existing passphrase
  collection (`collect_enc_passphrase` / `prompt_secret` / the
  `INSTALL_ENC_PASSPHRASE` VM seam) is reused verbatim; ZFS pipes it to
  `zpool create -O keylocation=prompt`, LUKS (`encryption_method: luks`, the
  non-ZFS default from ADR 0040) pipes the same secret to `cryptsetup luksFormat`.
  Boot-time unlock uses the classic mkinitcpio `encrypt` hook +
  `cryptdevice=UUID=…:cryptroot` (not SOPS keyfiles, not sd-encrypt).
- **Multi-volume key topology: one typed secret.** Only the **root** is unlocked
  by the typed passphrase (in initramfs). Encryption is a **per-group** flag
  independent of the root — a data group may be plaintext next to an encrypted
  root, or vice versa. An encrypted *data* group is auto-unlocked post-boot by a
  **keyfile stored on the (already-unlocked) encrypted root**, wired via generated
  `crypttab` / `zfs` key-load (new ground — no LUKS/crypttab today). Under
  impermanence that keyfile must live in the curated persist set / a
  never-rolled-back path, else it vanishes on reboot and the data volume fails to
  auto-unlock.
- **Layout dispatch splits in two.** A **Root Layout Adapter**
  (`root_adapter_source <fs> <mode>`) owns the OS disk — partition
  `ESP + [swap] + root`, format/create root, and emit a `ROOT_CMDLINE` fragment
  the FS-agnostic bootloader concatenates (mirrors the existing `ZSWAP_CMDLINE`
  pattern: ZFS → `root=ZFS=<pool>/ROOT`; ext4/xfs → `root=/dev/mapper/cryptroot`;
  btrfs adds `rootflags=subvol=…`). The Root Layout Adapter **also owns the
  initramfs `HOOKS` list** — `initcpio.sh` becomes FS-agnostic and writes
  whatever the active adapter declares (ZFS → `zfs [zfs-rollback] filesystems`;
  ext4/xfs → `[encrypt] filesystems`; btrfs → `[encrypt] [btrfs-rollback]
  filesystems`). A **Data Group Formatter**
  (`data_formatter_source <fs>`, mode-independent) formats one data group with
  its own FS. systemd-boot stays the default bootloader for all roots.
- **Swap leaves the pool.** Non-ZFS roots get a dedicated swap **partition**
  (LUKS-wrapped when the root is encrypted), sized from the existing `swap_size`
  logic; zswap is unchanged (cmdline-only, FS-agnostic). No btrfs swapfiles
  (nodatacow/snapshot footguns). Hibernate/`resume=` remains out of scope, as on
  ZFS today.
- **ZFS layout files relocate to `lib/layout/zfs/`** — the BASH_SOURCE root-
  sibling sourcing + chroot flat-copy lockstep hazard ADR 0040 deferred to
  "filesystem #2," now due.
- **Guided Installer lists only built adapters.** The FS picker enumerates
  exactly what dispatch can build (ZFS now; +ext4, then +btrfs as they land);
  topology lists are FS-conditional; the impermanence toggle is hidden unless the
  root FS is a snapshotting filesystem.

## Consequences

- **All four filesystems are first-class roots** — ext4/xfs roots are real
  supported targets (a pure ext4 machine is a legitimate setup), not data-only.
  Impermanence is still offered on zfs/btrfs roots only.
- btrfs impermanence is a separate decision — see ADR 0044.
- Build phasing: **ext4-root first** — it doubles as both a shipped product *and*
  the tracer bullet that isolates the shared non-ZFS boot/LUKS/`root=`/swap
  plumbing with zero filesystem cleverness — then xfs root (same shape, different
  mkfs), then btrfs root + impermanence on top.
