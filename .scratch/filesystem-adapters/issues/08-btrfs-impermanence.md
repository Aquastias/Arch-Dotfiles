# 08 — btrfs impermanence (per-path rollback, ADR 0044)

Status: done
Type: HITL

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Bring impermanence to a btrfs root by mirroring the ZFS per-path rollback model
(ADR 0044), reusing the existing curated/persist/resnapshot machinery. Swap only
the three filesystem-specific primitives behind a filesystem switch: create the
rollback subvolumes, snapshot each to `@blank` (`btrfs subvolume snapshot -r`),
and the boot-time rollback (an initramfs `btrfs-rollback` hook that
`subvolume delete`s + recreates from `@blank` per path, failing closed to an
emergency shell on a missing `@blank`). Persist `.mount` units order `After=` the
btrfs root mount instead of `zfs-mount.service`. The curated lists, `persist_*`
bind-mount verbs, manifest, and the PostTransaction re-snapshot pacman hook are
reused verbatim.

HITL: the boot-time rollback needs a live reboot test (like the prior ZFS
impermanence work), not just a headless smoke.

## Acceptance criteria

- [x] A btrfs root with impermanence enabled rolls the curated subtrees back to
      `@blank` on every boot; persisted paths and curated state survive.
      *(FS-layer built; boot behaviour pending HITL reboot.)*
- [x] The `btrfs-rollback` initramfs hook fails closed to an emergency shell when
      a `@blank` snapshot is missing.
- [x] Persist `.mount` units order after the btrfs root mount; machine-id / host
      keys / SOPS age key restore before early services (no dbus thrash).
      *(After= owning per-path subvol mount; FILES still COPY-frozen in @blank.)*
- [x] A package install survives a reboot (PostTransaction re-snapshot reused
      hook file; btrfs resnapshot helper body) — *reboot survival pending HITL.*
- [x] The FS-agnostic impermanence layer (curated lists, persist verbs, manifest,
      resnapshot hook) is unchanged and shared with ZFS.
- [x] bats covers the btrfs FS-layer (rollback-subvol creation, `@blank` snapshot
      calls, `btrfs-rollback` hook contents) with writes redirected under a temp
      ROOT, mirroring the existing ZFS impermanence tests.
- [x] Live reboot test confirms rollback (HITL). *(single + raid1 baselines GREEN;
      both negative controls RED for the right reason — see HITL results below.)*

## Progress (TDD, LOCAL/UNCOMMITTED)

Built via red→green slices; 1453 non-vm bats, 0 fail. Not yet committed.

- Slice 0: `FILESYSTEM` threaded through install-state (the FS-blind chroot
  modules' only discriminator).
- Rollback containers = subvolumes: `imp_btrfs_rollback_subvols` (from the same
  `ROLLBACK_DATASETS` source of truth) folds into the btrfs create/mount/fstab
  loops under impermanence (`@etc/@root/@opt/@srv/@usrlocal`). `/persist` is a
  plain dir on the never-rolled-back `@`.
- 3 FS-conditional primitives in `lib/chroot/impermanence.sh` (dispatch on
  `$FILESYSTEM`): `@blank` snapshot (`btrfs subvolume snapshot -r` over the
  subvolid=5 top-level), `btrfs-rollback` initramfs hook (`subvolume delete` +
  recreate from `@<name>@blank`, fail-closed on missing blank), PostTransaction
  resnapshot helper. zfs paths renamed `_zfs`, behaviour unchanged.
- Persist `.mount` After= → owning per-path subvol mount (`imp_mount_after_unit`:
  /etc/ssh→`etc.mount`, off-subvol→`-.mount`).
- HOOKS: `btrfs_hooks … impermanence` inserts `btrfs btrfs-rollback` before
  `filesystems` (no dup on multi); single+multi adapters pass the flag.
- Validation: `_validation_impermanence` skips the zfs `<pool>/<path>` rule for
  non-zfs (btrfs persist is a path, no pool).

Committed (local, UNPUSHED): `6f0b3fc` install-state FILESYSTEM, `629800b` btrfs
impermanence feature, `9698719` harness btrfs break-control.

Harness ready: `_seed_generator_rollback_firstboot_block` now takes a `filesystem`
arg (env `VM_ROLLBACK_FS=btrfs`) — btrfs seeds the sentinel via `subvol=@` mount
and the break-control deletes the `@etc@blank` subvol (subvolid=5 at /mnt), so the
automated two-boot `verify.rollback` test + its hook-fault negative control work on
btrfs. 1598 bats 0 fail.

Profiles ADDED (all resolve to configs passing `_validation_{filesystem,
group_filesystems,impermanence}`):
- `tests/vm/profiles/impermanence/btrfs.jsonc` — single, plaintext, verify.rollback.
- `tests/vm/profiles/impermanence/btrfs-raid1.jsonc` — 2-disk raid1, plaintext,
  verify.rollback. Harness `btrfs device scan`s before the live-ISO seed mount so
  the raid assembles.
- `tests/vm/profiles/impermanence/btrfs-encrypted.jsonc` — single, LUKS,
  INSTALL-ONLY (encrypted roots can't headless boot-verify — rollback HITL).
`vm.sh` auto-derives `VM_ROLLBACK_FS` from `install.filesystem` (no env override).

REMAINING (HITL — only open AC): run the live two-boot reboot test:
- baseline: `vm.sh -t tests/vm/profiles/impermanence/btrfs.jsonc --recreate`
  → boot2 emits `===FIRSTBOOT-OK===` (rollback reverted /root probe, /persist flag
  survived). Same for `btrfs-raid1.jsonc`.
- assertion control: same + `VM_ROLLBACK_PROBE_DIR=/persist` → probe survives →
  no marker → host RED (proves non-vacuous).
- hook-fault control: same + `VM_ROLLBACK_BREAK_BLANK=true` → boot1 deletes
  `@etc@blank` → boot2 hook fails closed (emergency shell) → RED.
- encrypted-single (`btrfs-encrypted.jsonc`): install-only → INSTALLER-EXIT-0,
  then boot by hand (`testtest`), manually do the two-boot probe/persist check.
Mirrors the ZFS 4-VM validation (`87b08f6`); enc-multi blocked (issue 07). Agent
env can't `git push` (~/.ssh denied) — USER pushes; VMs via `git daemon` +
`REPO_URL=git://192.168.122.1/.dotfiles`.

## HITL results (2026-07-03) — CLOSED

Live two-boot reboot HITL run from the agent env (git daemon serving local main,
`REPO_URL=git://192.168.122.1/.dotfiles`, `VM_RAM_MB=8192`).

**Bug the live reboot caught (invisible to bats — it mocks systemd/mount).** The
first baseline HUNG: boot1 came up in `systemd-firstboot` "Initial Setup" (console
stuck on the timezone prompt, `hostname=archlinux` fallback, a machine-id freshly
generated that boot). Root cause: the btrfs initramfs mounts only the `@` root
subvol; the rollback subvols (`@etc` …) were left to fstab, mounting at
`local-fs.target` — long AFTER PID1 reads `/etc/machine-id`/`/etc/hostname`. So
PID1 saw the empty `@/etc` mountpoint → `ConditionFirstBoot=yes` → firstboot ran
and blocked `multi-user.target`, so the rollback sentinel never fired → 600s
timeout. ZFS never hit this because the archzfs initramfs hook mounts the whole
dataset hierarchy (incl. `/etc`) under root before pivot.

**Fix (`f1d1d84`):** added a `run_latehook` to the `btrfs-rollback` hook that
mounts each recreated rollback subvol under `/new_root` (subvol→mountpoint pairs
baked from `ROLLBACK_DATASETS`) before `switch_root`, mirroring ZFS. systemd
later adopts them from fstab. RED→GREEN bats test added
(`chroot-impermanence.bats`: "mounts rollback subvols under /new_root (latehook)");
full suite 1600 green, shellcheck clean.

**4-VM validation (all as predicted):**
- `btrfs.jsonc` (single, plaintext) — INSTALLER-EXIT-0, boot2 `===FIRSTBOOT-OK===`,
  zero firstboot/Initial-Setup lines. GREEN.
- `btrfs-raid1.jsonc` (2-disk raid1) — raid assembled, INSTALLER-EXIT-0, boot2
  `===FIRSTBOOT-OK===`, no hang. GREEN.
- `+ VM_ROLLBACK_PROBE_DIR=/persist` — system boots cleanly (login reached), probe
  survives on `/persist`, NO marker → host RED (exit 125). Proves non-vacuous.
- `+ VM_ROLLBACK_BREAK_BLANK=true` — boot2 logs
  `ERROR: impermanence: @blank snapshot missing for @etc` → emergency shell, NO
  marker → host RED (exit 125). Proves fail-closed.

**enc-single (`btrfs-encrypted.jsonc`) — INSTALL VM-verified 2026-07-03 with the
fix:** LUKS root opened → `/dev/mapper/cryptroot`, initramfs built with the hooks
in the right order (`encrypt → btrfs → btrfs-rollback`, so cryptroot opens before
the rollback hook runs), `===INSTALLER-EXIT-0===`. Profile stays **install-only**;
the two-boot rollback proof stays **by-hand** (`testtest`, write /root probe +
/persist flag, reboot, confirm probe GONE + flag SURVIVED).

**Headless-encrypted-verify ATTEMPT (2026-07-03) — prototyped, not landed.**
I prototyped a harness path to headless-verify an encrypted root: add `console=ttyS0`
via a verify block + a serial-console driver (one process owns the serial PTY and
types the LUKS passphrase at the cryptsetup prompt). The passphrase-answering WORKS
— boot1 unlocked `/dev/mapper/cryptroot`, reached multi-user with the REAL hostname
and NO firstboot hang (the `f1d1d84` early-mount fix works under LUKS), and the
`btrfs-rollback` hook ran on encrypted. BUT the encrypted btrfs-impermanence system
**reboot-LOOPS** once `console=ttyS0` + serial input are active: 4-5 boots, the
firstboot sentinel never lands its `===FIRSTBOOT-OK===`, `Failed to start Save
Transient machine-id to Disk`, abrupt firmware resets right after each getty. The
loop persists with a single-boot (non-rollback) sentinel too, so it is NOT the
rollback `/persist`-flag logic — it is a serial-console/getty/impermanence-under-LUKS
interaction needing live hands-on debugging (credentials + journal), out of reach of
the headless agent. The prototype was discarded (not landed) to keep the suite
clean; the approach is recorded here for a future follow-up. The rollback MECHANISM
is proven on encrypted (hook runs, clean boot); the AC's live rollback proof is
satisfied by the plaintext single+raid1 two-boot runs + controls.
enc-multi still blocked by issue 07. `f1d1d84` PUSHED.

**Follow-up (deferred):** debug the encrypted btrfs-impermanence serial-console
reboot loop (`console=ttyS0` + getty), then re-land headless encrypted boot-verify
via the serial-driver approach.

## Blocked by

- `07` (btrfs root boots)
