# ADR 0038: Boot-path resilience on a small FAT ESP

## Status
Accepted. Builds on ADR 0023 (single-source ZFS module install),
ADR 0024 (Kernel Selection / Primary Kernel / ZFS Module Guard), and
ADR 0030 (boot-time ZFS import).

## Context
systemd-boot cannot read ZFS, so the kernel image and initramfs are
copied from the ZFS `/boot` onto the FAT32 ESP by the **ESP Kernel
Sync** hook on every kernel transaction.

That hook shipped two silent foot-guns. It ran a bare `cp` with no
exit check and a `linux*` glob. On an lts-only host, a **Stray
Kernel** (a rolling `linux` pulled in after install, outside the
installer) plus the default **512M** ESP overflowed mid-`pacman -Syu`:
the `cp` truncated the initramfs, pacman ignored the failure, and the
next boot was `Kernel panic — no working init found`. Recovering by
deleting the unused `amd-ucode.img` then left a dangling
`initrd /amd-ucode.img` line, which systemd-boot treats as a fatal
"Error preparing initrd". Two independent silent failures, one brick.

Root causes: 512M is too small to hold even one kernel's default +
fallback comfortably, let alone a stray second kernel; the sync was
unconditional, unverified, and not microcode-vendor-aware; and nothing
guards the ESP at upgrade time — the install-time ZFS Module Guard
(ADR 0024) never runs on `-Syu`.

## Decision
1. **ESP sizing.** `esp_size` default 512M → **2G**, centralized (the
   per-profile pins are stripped so profiles inherit it); **1G hard
   floor**, the installer errors below it.
2. **ESP Kernel Sync is fail-closed.** It mirrors only
   Kernel-Selection kernels and the microcode files actually present.
   A **PreTransaction** space preflight aborts the upgrade early when
   the ESP cannot hold the images; the **PostTransaction** copy writes
   a temp file then renames (so a failed copy leaves the prior good
   image intact), `cmp`-verifies the critical default image, and
   sweeps orphaned `.new` temps. Any copy failure fails the pacman
   transaction loudly instead of truncating silently.
3. **Stray Kernel = warn, not block.** A kernel not in Kernel
   Selection is isolated — it never reaches the ESP, systemd-boot
   entries name only the Primary Kernel, and under GRUB `GRUB_DEFAULT`
   is pinned to the Primary Kernel so a higher-sorting stray cannot
   auto-boot — and surfaced by a non-blocking upgrade-time warn hook
   that reuses the ZFS Module Guard's `zfs.ko`-presence check.
4. **Per-vendor microcode.** Detect the CPU vendor at install and
   install only that `*-ucode`; loader entries and the sync are
   generated from the `*-ucode.img` files present, so an entry never
   references a missing initrd.
5. **Fallback initramfs** is kept on a 2G ESP (a no-USB recovery
   entry) and omitted on a retrofitted 512M ESP; entry presence always
   tracks image presence.
6. **Single source.** All runtime artifacts (the sync script, the
   preflight, the warn hook, their `.hook` files) live in one shared
   dir, staged by the bootloader adapters and installed by the
   retrofit tool `tools/harden-boot.sh` — the ADR 0023 pattern — with
   lib-only-source guards so the pure helpers are bats-testable.

## Considered alternatives
- **Keep 512M, only fix the hook.** The hook fix stops the truncation,
  but 512M still cannot hold a fallback plus any second kernel; 2G
  removes the pressure that created the foot-gun in the first place.
- **Block stray kernels** (`IgnorePkg` / PreTransaction veto).
  Heavy-handed: breaks a legitimate out-of-repo dependency, and
  sync-isolation + the GRUB default-pin already make a stray
  boot-harmless. Warning is sufficient.
- **Install both microcodes, reference only present files.** Fixes the
  dangling reference but keeps the unused vendor's blob on a
  space-constrained ESP; per-vendor is cleaner and smaller.
- **PostTransaction-only guard.** Lets a full-ESP transaction complete,
  leaving a bootable-but-degraded old kernel whose module tree was just
  removed. The preflight aborts before reaching that state.

## Consequences
- New installs partition a 2G ESP. Existing 512M machines cannot be
  repartitioned but gain the hardened hook, the guards, and the GRUB
  default-pin via `harden-boot.sh` (fallback omitted to keep headroom).
- A boot image can never be silently truncated again: a full ESP
  either aborts the upgrade (preflight) or fails the transaction loudly
  with the prior image intact (temp+rename+cmp).
- A Stray Kernel is boot-harmless and surfaced, not silently
  bricking; the operator decides whether to remove it.
- The **ESP Kernel Sync** and the **ESP Mirror Hook** are now distinct,
  documented concerns, ordered Kernel-Sync-before-Mirror (correcting
  the old `95`/`96` numbering that ran them backwards).
- Depends on ADR 0024 for the selected-kernel set and the reused
  module check, and on ADR 0023 for the single-source artifact pattern.

## Amendment (2026-06-23): preflight correctness + exec/mount guards

A real 512M box bricked on its first kernel `-Syu` and exposed two gaps
the original decision missed.

1. **Preflight false-abort on a populated ESP.** `esp_sync_needed_bytes`
   returns `total + max` (the temp+rename peak) and the preflight checked
   it against *free* space. But on any ESP that already holds the prior
   kernel set, `total` is already *on* the ESP — counted as used (so
   absent from free) and again as needed. The check demanded
   `free ≥ total + max` when a re-sync only needs the transient `.new` of
   the largest file. On a 512M ESP with a 181M initramfs this aborted
   every kernel upgrade (fail-safe, but a hard block). Fix: subtract the
   planned files already present (`esp_sync_present_bytes`); the budget
   is now `free + present ≥ total + max` — identical on a first/empty
   write, correct on a re-sync, and still aborting a genuinely-too-small
   ESP.

2. **The bricking foot-gun was a non-space failure the preflight never
   covered.** The installed sync script lacked a valid `#!` shebang
   (a WIP build), so the PostTransaction hook's `Exec=` — which pacman
   sends straight to `execv` with no shell — failed `ENOEXEC` ("Exec
   format error"). pacman logged it and moved on; the new kernel never
   reached the ESP; the next boot ran the stale image whose modules the
   same upgrade had deleted (`vfat` then could not load, so `/boot/efi`
   itself would not mount). The same silent-stale-ESP result follows if
   `/boot/efi` is simply not mounted at upgrade time (the sync writes
   into the ZFS directory).

   The structural fix is that the **PreTransaction `AbortOnFail`
   preflight** turns *any* hook failure — including the script's own
   `ENOEXEC` — into an aborted upgrade *before* the kernel is swapped, so
   the system can never reach the bricked state. On top of that the
   preflight now self-asserts, fail-closed, before space:
   `esp_sync_script_ok "$0"` (the shared 93/94 script is an executable
   with a `#!`) and `esp_sync_is_mountpoint` for every `/boot/efi*`. The
   runtime sync also refuses to run when an ESP is unmounted, rather than
   silently mirroring into the ZFS directory. The mountpoint guard is
   also the precondition that makes a future `nofail` ESP mount safe.

All three helpers are pure and lib-only-testable. Existing 512M installs
adopt the corrected preflight + guards by re-running
`tools/harden-boot.sh` (which overwrites the script with the current
single-source version); a stale legacy `96-esp-kernel-sync.hook` from a
pre-renumber build must be removed by hand.
