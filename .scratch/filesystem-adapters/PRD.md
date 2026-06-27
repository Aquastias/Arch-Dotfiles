# Filesystem Adapters — btrfs/ext4/xfs roots + per-group filesystem selection

Status: ready-for-agent

Decisions of record: **ADR 0043** (per-group filesystem & layout-adapter split)
and **ADR 0044** (btrfs impermanence via per-path rollback), both extending
**ADR 0040** (Filesystem Adapter axis) and building on ADR 0036 (unified
profile / Effective Config), 0034 (layout planner/executor split), 0030
(boot-time zfs import), 0024 (kernel selection + ZFS module guard), 0023
(archzfs-compatible ISO).

Glossary touched (`CONTEXT.md`, already updated): Filesystem Adapter (rewritten),
Root Layout Adapter (new), Data Group Formatter (new); also Layout Module,
Bootloader Adapter, Impermanence, Rollback Datasets, ZFS Module Guard,
archzfs-Compatible ISO.

## Problem Statement

The installer only does ZFS. I want a btrfs root so I can still get
impermanence on a non-ZFS machine, and I want to put a plain ext4 (or xfs) disk
alongside it — or build a whole ext4 machine — without the installer fighting
me. Today every disk is forced into a ZFS pool, encryption is ZFS-native only,
impermanence is ZFS-dataset-only, and the boot path hardcodes `root=ZFS=`. A
"select the filesystem per disk-group" machine is simply not expressible.

## Solution

A machine's **OS/root filesystem** is chosen from `zfs | btrfs | ext4 | xfs`, and
each **data group** may independently pick its own filesystem (defaulting to the
root's). The installer dispatches the OS disk to a **Root Layout Adapter** (keyed
by filesystem × mode) that owns partitioning, formatting, the `root=` cmdline,
and the initramfs `HOOKS`; each data group is formatted by a **Data Group
Formatter** (keyed by filesystem). ZFS and btrfs carry native multi-disk
topology; ext4/xfs are single-disk only. Encryption is per-group and
filesystem-aware: ZFS native AES, everything else LUKS, with **one** passphrase
typed at boot (root) and data volumes auto-unlocked from a keyfile on the root.
Impermanence works on ZFS **and** btrfs roots, using the same curated/persist
machinery with a filesystem-specific rollback primitive. The Guided Installer
exposes only filesystems whose adapter is built, gates topology and impermanence
per filesystem, and offers a per-group filesystem + encryption choice.

## User Stories

1. As an operator, I want to choose my root filesystem from zfs/btrfs/ext4/xfs,
   so that I am not locked into ZFS.
2. As an operator installing a btrfs root, I want impermanence, so that my
   system rolls back to a clean state every boot without ZFS.
3. As an operator, I want to keep a ZFS root but add an ext4 data disk, so that
   ordinary data lives on a simple filesystem.
4. As an operator, I want a pure ext4 machine (root + data all ext4), so that I
   can run a minimal CoW-free system.
5. As an operator, I want an xfs root or xfs data group, so that I can use xfs
   for large-file workloads.
6. As an operator, I want each data group to declare its own filesystem
   independent of the root, so that one machine can mix filesystems by group.
7. As an operator, I want a data group's filesystem to default to the root's
   filesystem when I don't specify it, so that simple single-filesystem machines
   need no extra fields.
8. As an operator picking ext4/xfs for a group, I want the installer to reject
   `disk_count > 1` for that group, so that I'm not misled into thinking it
   provides redundancy.
9. As an operator, I want btrfs groups to offer native raid0/1/10 topology, so
   that I get redundancy without mdadm/LVM.
10. As an operator, I want ZFS groups to keep mirror/raidz/stripe topology, so
    that nothing about the existing ZFS path regresses.
11. As an operator with an encrypted non-ZFS root, I want to type one passphrase
    at boot, so that unlocking is no more painful than the ZFS path.
12. As an operator, I want each data group to opt into encryption independently,
    so that I can have a plaintext scratch disk next to an encrypted root (or the
    reverse).
13. As an operator, I want encrypted data groups to auto-unlock after the root is
    open, so that I only ever type one secret per boot.
14. As an operator running impermanence on btrfs, I want my data-group unlock
    keyfile to survive the boot-time rollback, so that encrypted data still
    mounts after a reboot.
15. As an operator on ext4/xfs root, I want the impermanence toggle hidden, so
    that I'm not offered a feature the filesystem can't provide.
16. As an operator, I want swap on a non-ZFS root to live on a dedicated
    (LUKS-wrapped when encrypted) partition, so that swap is encrypted and
    hibernate-friendly plumbing stays uniform.
17. As an operator, I want zswap to keep working regardless of filesystem, so
    that my recent zswap setup is unaffected.
18. As an operator booting a non-ZFS root, I want the correct `root=` and
    initramfs hooks generated automatically, so that the machine boots without
    manual cmdline surgery.
19. As an operator building a pure non-ZFS machine with no ZFS group anywhere, I
    want the installer to skip zfs userland, the ZFS module guard, and the
    archzfs ISO requirement, so that a vanilla install isn't burdened by ZFS.
20. As an operator with an ext4 root but a ZFS data pool, I want zfs userland +
    boot-time import present, so that the data pool still imports at boot.
21. As an operator in the Guided Installer, I want a root-filesystem picker that
    lists only filesystems the installer can actually build, so that I can't pick
    a broken path.
22. As an operator in the Guided Installer, I want topology choices to change
    with the selected filesystem, so that I only see valid options.
23. As an operator in the Guided Installer, I want a per-group filesystem and
    encryption choice in the data-pool editor, so that I author mixed-filesystem
    machines interactively.
24. As an operator authoring a Host Profile by hand, I want per-group
    `filesystem`/`encryption` to be additive optional fields validated against
    the closed schema, so that existing ZFS profiles keep loading unchanged.
25. As a maintainer, I want a btrfs-root install to reuse the existing
    curated-persist + resnapshot machinery, so that there is one impermanence
    architecture, not two.
26. As a maintainer, I want the bootloader and initcpio modules to be
    filesystem-agnostic, so that a new filesystem is an additive adapter, not an
    edit to shared boot code.
27. As a maintainer, I want the existing ZFS install path to behave identically
    after the relocation into `lib/layout/zfs/`, so that the refactor is
    behavior-preserving.

## Implementation Decisions

### Schema & validation
- Top-level `filesystem` names the **OS/root** filesystem (unchanged role: drives
  `encryption_method` default + impermanence eligibility). Data groups
  (`storage_groups[]`, `data_pools[]`) gain an **optional** `filesystem` that
  defaults to the root value, and an **optional per-group `encryption`** bool
  independent of the root. Purely additive — no migration; existing ZFS profiles
  validate unchanged.
- Validation contract: `filesystem ∈ {zfs,btrfs,ext4,xfs}` (already present);
  topology is filesystem-conditional (zfs → mirror/raidz1/raidz2/stripe; btrfs →
  single/raid0/raid1/raid10; ext4/xfs → single only, `disk_count > 1` rejected);
  `encryption_method` derives native↔zfs / luks↔else (already present);
  impermanence requires root `filesystem ∈ {zfs,btrfs}` (already present).

### Dispatch & adapters
- `lib/layout/dispatch.sh` gains `root_adapter_source <fs> <mode>` (boot/partition
  /root) and `data_formatter_source <fs>` (one group, mode-independent).
- ZFS layout files relocate into `lib/layout/zfs/` (BASH_SOURCE root-sibling +
  chroot flat-copy lockstep hazard — handle per the lib-foldering gotcha). The
  ZFS data-pool creation becomes the ZFS Data Group Formatter.
- New ext4/xfs/btrfs Root Layout Adapters partition `ESP + [swap] + root`, format
  root, and emit a `ROOT_CMDLINE` fragment + a `HOOKS` list. New Data Group
  Formatters for ext4/xfs/btrfs.

### Boot & initramfs (made filesystem-agnostic)
- The Root Layout Adapter emits `ROOT_CMDLINE` (zfs → `root=ZFS=<pool>/ROOT`;
  ext4/xfs → `root=/dev/mapper/cryptroot` or `root=UUID=…`; btrfs adds
  `rootflags=subvol=…`) which the bootloader concatenates, mirroring the existing
  `ZSWAP_CMDLINE` pattern. The adapter also owns the initramfs `HOOKS` list
  (zfs → `zfs [zfs-rollback] filesystems`; ext4/xfs → `[encrypt] filesystems`;
  btrfs → `[encrypt] [btrfs-rollback] filesystems`); `initcpio.sh` writes
  whatever the active adapter declares. systemd-boot stays the default bootloader.

### Encryption
- One shared passphrase seam reused verbatim (`collect_enc_passphrase` /
  `prompt_secret` / the `INSTALL_ENC_PASSPHRASE` VM seam); only the consumer
  differs — ZFS pipes to `zpool create -O keylocation=prompt`, LUKS pipes the
  same secret to `cryptsetup luksFormat`. Boot-time LUKS unlock via the classic
  mkinitcpio `encrypt` hook + `cryptdevice=UUID=…:cryptroot`.
- Multi-volume key topology: only the **root** is unlocked by the typed
  passphrase (initramfs). Encrypted **data** groups are auto-unlocked post-boot by
  a **keyfile stored on the encrypted root**, via generated `crypttab` / `zfs`
  key-load. Under impermanence the keyfile must live in the curated persist set /
  a never-rolled-back path.

### Swap
- Non-ZFS roots get a dedicated swap **partition** (LUKS-wrapped when root is
  encrypted), sized from the existing `swap_size` logic. zswap unchanged
  (cmdline-only). No btrfs swapfiles. Hibernate/`resume=` out of scope, as today.

### btrfs impermanence (ADR 0044)
- Mirror the ZFS per-path rollback model, not full-root-wipe. Reuse
  `impermanence-common.sh` curated lists, `persist_*` bind-mount verbs, the
  manifest, and the PostTransaction re-snapshot pacman hook verbatim. Swap only
  three primitives behind a filesystem switch: create rollback subvolume
  (`btrfs subvolume create`), snapshot-blank (`btrfs subvolume snapshot -r …
  @blank`), and the boot rollback (initramfs `btrfs-rollback` hook: `subvolume
  delete` + recreate from `@blank` per path, failing closed to an emergency shell
  if a `@blank` is missing). Persist `.mount` units order `After=` the btrfs root
  mount instead of `zfs-mount.service`.

### ZFS-presence gating
- Derive "any group is zfs" across root + all data groups. zfs userland, the
  boot-time pool import, the ZFS Module Guard, and the archzfs-compatible ISO
  requirement are gated on that condition. A machine with no ZFS group anywhere
  needs none of them; an ext4-root + ZFS-data machine still needs import +
  module.

### Guided Installer
- Root-filesystem picker lists only built adapters (ZFS now; +ext4, +xfs, +btrfs
  as they land). Topology lists are filesystem-conditional. Per-group filesystem
  + encryption surface in the data-pool editor. Impermanence toggle hidden unless
  root `filesystem ∈ {zfs,btrfs}`.

### Phasing (tracer-bullet slices)
1. Schema + accessors + validation (per-group `filesystem`/`encryption`,
   topology contract) — no behavior change to ZFS.
2. Dispatch split + relocate ZFS into `lib/layout/zfs/` — behavior-preserving.
3. **ext4 root** (Root Adapter + non-ZFS partition/LUKS planner + crypttab
   emitter + `ROOT_CMDLINE`/`HOOKS` + swap partition + zfs-presence gating) —
   shipped product *and* tracer for all non-ZFS-root plumbing.
4. ext4/xfs/btrfs **Data Group Formatters** (incl. mixing with a ZFS root).
5. **xfs root** (same shape as ext4, different mkfs).
6. **btrfs root + impermanence** (subvolumes, native topology, ADR 0044
   rollback).
7. Guided Installer per-group FS/encryption UX + gating.

## Testing Decisions

A good test asserts external behavior, not implementation: it feeds an input
(config JSON, disk/size params, a filesystem+mode) and checks the observable
output (emitted text, returned device plan, files written under a redirected
`ROOT`), never internal call sequences. Mirror existing bats prior art:
`config/validation` tests for the schema contract, the impermanence tests that
redirect writes under a temp `ROOT`, and the existing layout/dispatch tests.

Bats coverage targets the **deep cores** (the rest is VM-smoke-gated, like the
current ZFS path):
- **Layout dispatch** — `root_adapter_source` / `data_formatter_source` string
  mapping incl. the unbuilt-filesystem error (extends existing dispatch tests).
- **Non-ZFS partition/LUKS planner** — given disk + sizes + encrypt flag, asserts
  the ESP/swap/root partition plan + LUKS container plan + resolved device paths.
- **Crypttab / zfs-key-load emitter** — per-group encryption → expected crypttab
  text + keyfile placement path; round-trips a stored `false` correctly (jq
  bool gotcha).
- **`ROOT_CMDLINE` + `HOOKS` emitters** — per adapter, exact string per
  filesystem (zfs/ext4/xfs/btrfs, encrypted vs not, impermanence on/off).
- **btrfs impermanence FS-layer** — with writes redirected under a temp `ROOT`,
  assert rollback-subvolume creation, `@blank` snapshot calls, and the
  `btrfs-rollback` initramfs hook contents (fail-closed on missing `@blank`),
  mirroring the existing ZFS impermanence tests.
- **Validation contract** — per-group filesystem/topology rules: ext4/xfs reject
  `disk_count > 1`; btrfs accepts raid0/1/10; impermanence rejected on
  ext4/xfs root; encryption_method derivation per filesystem.

## Out of Scope

- mdadm / LVM (no software-RAID or volume-manager axis for ext4/xfs).
- Hibernate / `resume=` (unchanged from today's ZFS path).
- btrfs swapfiles (swap is always a partition on non-ZFS roots).
- SOPS-managed LUKS keyfiles / sd-encrypt / TPM enrollment (classic `encrypt`
  hook + keyfile-on-root only).
- bcachefs or any filesystem beyond zfs/btrfs/ext4/xfs.
- Changing the ZFS install path's behavior (the relocation must be
  behavior-preserving).
- A strict-mode impermanence drift workflow (still the deferred v2 item).

## Further Notes

- The ext4-root slice is the critical tracer: it exercises every shared non-ZFS
  primitive (partition/LUKS/swap/`root=`/`HOOKS`/crypttab/zfs-presence gating)
  with zero filesystem cleverness, so btrfs root later is "ext4 root + subvolumes
  + snapshot rollback."
- VM smoke caveats from prior art: encrypted roots can't headless boot-verify;
  run one VM per background job; serve the repo via `git daemon` + `REPO_URL`
  override (no push). A pure-ext4 install may be the easiest non-ZFS root to
  boot-verify headless.
- Watch the `lib/layout/zfs/` relocation for the BASH_SOURCE root-sibling
  sourcing + chroot flat-copy / kde.sh lockstep hazard recorded in the
  lib-foldering gotcha.
- **Open question (layout slices 05/07):** per-group `filesystem` is accepted on
  **both** `data_pools[]` and `storage_groups[]` (operator's call). But a
  Storage Group folds into the single **Combined Data Pool** (one zpool) — a
  non-ZFS storage group can't fold into a ZFS pool. The layout slices must decide
  what a non-ZFS storage group *means* (promote it to a standalone pool? reject
  the combination?). The schema/validation slice (01) deliberately allows it; the
  formatter slices resolve the semantics.
