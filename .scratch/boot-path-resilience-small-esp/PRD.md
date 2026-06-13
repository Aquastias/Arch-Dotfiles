# PRD: Boot-path resilience on a small FAT ESP

Status: done

References: ADR 0038 (this feature), ADR 0024 (Kernel Selection /
Primary Kernel / ZFS Module Guard), ADR 0023 (single-source ZFS
module install), ADR 0030 (boot-time ZFS import). Glossary: ESP
Kernel Sync, ESP Mirror Hook, Stray Kernel, Kernel Selection,
Primary Kernel, ZFS Module Guard, Base Package List, GPU Resolution,
Layout Module, Bootloader Adapter, Tools.

## Problem Statement

A person installed Arch on ZFS with the `arch-kde` profile
(systemd-boot, `linux-lts` only, single disk). Two weeks later a
routine `pacman -Syu` left the machine unbootable: `Kernel panic —
not syncing: No working init found`. The kernel had loaded an
initramfs that contained no `/init` — the image on the FAT32 ESP was
truncated.

Three things combined. First, a rolling `linux` kernel had been
installed alongside `linux-lts` (a **Stray Kernel** — not in the
host's **Kernel Selection**, pulled in from outside the installer).
Second, the **ESP Kernel Sync** hook copied kernels to the ESP with a
`linux*` glob, so it shovelled *both* kernels' images onto the disk.
Third, the ESP was only **512M** — too small to hold two kernels'
images plus fallbacks — so the `cp` ran out of space and silently
truncated the initramfs. The hook never checked the `cp` exit code, so
the broken image was committed and the transaction "succeeded."

Recovery surfaced a second silent foot-gun: deleting the unused
`amd-ucode.img` (the board is Intel) left a dangling `initrd
/amd-ucode.img` line in the loader entry, which systemd-boot treats as
a fatal "Error preparing initrd: Not found". Nothing in the system
guards the ESP at upgrade time — the **ZFS Module Guard** only runs at
install (ADR 0024), never on `-Syu`.

## Solution

Make the boot path on a FAT ESP impossible to silently brick, and stop
shipping the conditions that caused it.

Give new installs a **2G ESP** by default (with a 1G hard floor) so the
images always fit. Harden the **ESP Kernel Sync** so it mirrors only
the kernels in Kernel Selection and only the microcode actually
present, refuses to truncate (a space preflight aborts the upgrade
early; the copy writes-then-renames so the prior good image survives;
the critical image is `cmp`-verified), and **fails the pacman
transaction loudly** rather than committing a broken boot. Treat a
Stray Kernel as **warn, not block**: it never reaches the ESP, the
boot default always points at the **Primary Kernel** (under both
bootloaders), and an upgrade-time warn hook surfaces it. Install only
the CPU's own microcode and generate loader entries from the files
that exist, so an entry can never reference a missing initrd. Ship a
bootloader-aware retrofit tool so an already-installed machine gets the
same protections without a reinstall. The user's machine boots; future
upgrades cannot truncate the boot image; a stray kernel is harmless and
visible.

## User Stories

1. As a person booting my machine, I want a `pacman -Syu` to never
   leave me at a kernel panic, so that updates are safe.
2. As an operator running an upgrade, I want a full ESP to abort the
   upgrade *before* anything is applied, so that I can free space and
   retry from a clean state.
3. As an operator, I want a failed copy to the ESP to keep my previous
   working boot image intact, so that a botched sync never costs me a
   bootable system.
4. As an operator, I want the ESP Kernel Sync to fail the pacman
   transaction loudly when it cannot write a complete boot image, so
   that I find out before I reboot, not after.
5. As an operator, I want the critical default initramfs on the ESP
   byte-verified against its `/boot` source after copy, so that a
   silently corrupt copy is caught.
6. As a person installing a new machine, I want a 2G ESP by default, so
   that kernel images, microcode, and a fallback always fit with room
   to grow.
7. As an operator, I want the installer to reject an `esp_size` below
   1G, so that I cannot accidentally recreate the too-small ESP that
   caused this.
8. As a maintainer, I want a single centralized ESP-size default rather
   than the value pinned in every profile, so that it cannot drift.
9. As an operator on an lts-only host, I want a rolling `linux` that
   slipped in to never reach the ESP, so that it cannot crowd out my
   real kernel's images.
10. As an operator, I want a Stray Kernel surfaced with a loud warning
    at upgrade time, so that I can decide whether to remove it.
11. As an operator, I want a Stray Kernel to never become the default
    boot entry under systemd-boot, so that I always boot my Primary
    Kernel.
12. As a GRUB user, I want the Primary Kernel pinned as the default
    even when a stray kernel sorts higher by version, so that a
    possibly-unbootable stray never auto-boots.
13. As an operator, I want a kernel that cannot build `zfs.ko` flagged
    at upgrade time (reusing the install-time check), so that a broken
    ZFS module is never a silent trap.
14. As an operator on an Intel board, I want only `intel-ucode`
    installed, so that I am not carrying AMD microcode I will never use.
15. As an operator on an AMD board, I want only `amd-ucode` installed,
    for the same reason.
16. As an operator, I want loader entries generated from the microcode
    files that actually exist, so that an entry never references a
    missing initrd.
17. As a person, I want a fallback initramfs and recovery boot entry on
    my 2G ESP, so that I can recover without a USB stick.
18. As an operator retrofitting a 512M machine, I want the fallback
    omitted there, so that the tight ESP keeps headroom for the default
    image.
19. As an operator, I want the fallback boot entry to exist only when
    its image exists, so that selecting it never dead-ends on a missing
    initrd.
20. As an operator of an already-installed machine, I want a tool that
    installs the hardened hook, the warn hook, the per-vendor microcode
    fix, and the default-pin without a reinstall, so that my running
    system gains the protections.
21. As an operator, I want the retrofit tool to be idempotent and offer
    a `--dry-run`, so that I can preview exactly what it will change.
22. As an operator, I want the retrofit tool to never repartition, so
    that running it is low-risk.
23. As an operator on a GRUB host, I want the retrofit to apply the
    GRUB-relevant fixes (default-pin, per-vendor microcode), so that
    GRUB machines are covered too.
24. As an owner of a multi-disk OS mirror, I want the ESP Kernel Sync
    to run before the ESP Mirror Hook, so that my secondary ESPs
    receive the freshly-synced images, not stale ones.
25. As a maintainer, I want the hardened scripts to live in one shared
    place used by both the installer and the retrofit tool, so that the
    two cannot drift apart.
26. As a maintainer, I want the pure decision logic unit-tested in
    isolation, so that a regression in "which files get copied" or "is
    there room" is caught in CI.
27. As a maintainer, I want an end-to-end check that plants the brick
    precondition and asserts the guards fire, so that the exact failure
    that happened cannot silently return.
28. As an operator, I want the existing install-time ZFS Module Guard
    behavior unchanged for the supported lts path, so that this work
    adds protection without disrupting a working install.

## Implementation Decisions

**ESP size policy (deep module).** The Layout Module's ESP-size
resolution gains a 2G default and a validator: an `esp_size` resolving
below 1G is a fail-fast install error (consistent with the repo's
config-validation style). The default lives in exactly one place; the
explicit `esp_size` pins are removed from every host profile and every
test profile so they inherit it. Interface: pure functions taking the
configured size string and returning a resolved size and a validation
result.

**ESP Kernel Sync hardening (deep module).** Extracted from the
systemd-boot Bootloader Adapter heredoc into a standalone, shared
artifact (with a lib-only-source guard for tests). Its planner is pure:
given the Kernel Selection set, the boot files present, and the ESP
free space, it yields the critical copies (Primary Kernel image,
present microcode, default initramfs), the optional copies (fallback,
secondary ESPs), and a go/no-go. The runtime wrapper: a PreTransaction
pacman hook aborts the upgrade when ESP free space is below a proxy for
the images' size; the PostTransaction hook copies each critical file
via temp-file-then-rename (so a failed copy leaves the prior image
intact), `cmp`-verifies the critical default against its `/boot`
source, sweeps orphaned `.new` temps, and exits non-zero (failing the
transaction) on any critical failure. Optional files are best-effort
and self-clean a truncated remnant. The sync is driven by the Kernel
Selection list, never a `linux*` glob, so a Stray Kernel never reaches
the ESP.

**Microcode resolution (deep module).** CPU vendor is detected at
install (the same `lspci`/`cpuinfo` approach GPU Resolution uses) and
only the matching `*-ucode` is added to the Base Package List
(replacing the unconditional both-vendors entry). Loader entries and
the ESP Kernel Sync derive their microcode `initrd` lines from the
`*-ucode.img` files that exist. Interface: pure vendor-to-package
mapping and present-files-to-entry-lines.

**Stray Kernel detector (deep module).** A pure classifier over the
installed kernels, the Kernel Selection, and the kernel module trees,
reusing the ZFS Module Guard's existing `zfs.ko`-presence check, that
returns the Stray and/or `zfs.ko`-less kernels. Consumed by a
non-blocking upgrade-time warn pacman hook that prints the finding;
it never removes or blocks.

**Bootloader default pinning.** systemd-boot entries continue to name
only the Primary Kernel (already the case). The GRUB common installer
pins `GRUB_DEFAULT` to the Primary Kernel's entry so a higher-sorting
stray cannot become the default; per-vendor microcode in GRUB is
already handled by `grub-mkconfig` enumerating present files.

**Hook ordering.** The ESP Kernel Sync and the ESP Mirror Hook are
distinct concerns and must run Kernel-Sync-before-Mirror; the hook
numbering is corrected so the secondary-ESP mirror sees freshly-synced
images.

**Retrofit tool.** A new bootloader-aware Tool, `harden-boot.sh`,
idempotent with `--dry-run`, that never repartitions. On a
systemd-boot host it installs the hardened ESP Kernel Sync + warn hook,
reconciles per-vendor microcode and loader entries, and drops the
fallback when the ESP is under ~1G. On a GRUB host it pins the default
to the Primary Kernel and re-runs the microcode-aware config. It and
the bootloader adapters install from the same shared artifacts.

## Testing Decisions

Good tests here assert external behavior, not implementation: given
inputs, the module returns the right decision — they do not reach into
private helpers or assert on file layout. All four deep modules get
bats unit tests:

- **ESP size policy** — resolve + 1G-floor validation (size string in →
  resolved value / error). Prior art: the existing `layout-common`
  bats covering `layout_resolve_esp_size`.
- **ESP Kernel Sync planner** — the highest-value tests: which
  kernels/files are selected to copy (only Kernel Selection, only
  present microcode), the space go/no-go proxy, the cmp-gate outcome,
  and the `.new` sweep decision, over fixtures. Lib-only source, no real
  ESP needed.
- **Microcode resolution** — vendor-to-package mapping and
  present-file-to-entry-`initrd` lines, including the "missing vendor
  file ⇒ no dangling reference" case.
- **Stray Kernel detector** — Stray and `zfs.ko`-less classification
  over a fixture module tree, reusing the ZFS Module Guard check.

End-to-end, the orchestration (the runtime hooks, the retrofit tool,
the adapter wiring) is exercised by extending the VM Harness's existing
first-boot sentinel: a first-boot check plants the brick precondition
(a deliberately tight/filled ESP plus a planted Stray Kernel), runs the
hardened ESP Kernel Sync, and emits the success sentinel only if the
guard fails loudly, preserves the prior image, and the warn hook
reports the stray. No second reboot is required — it reuses the
`firstboot-ok.service` sentinel mechanism. Prior art: the existing VM
smoke gates and `vm-pool-verify`.

## Out of Scope

- Repartitioning or growing an existing 512M ESP to 2G. Existing
  machines keep their ESP and gain only the hook/guard/default-pin via
  the retrofit tool.
- Blocking or auto-removing a Stray Kernel (IgnorePkg, PreTransaction
  veto, or uninstall). The decision is warn-not-block; isolation plus
  the default-pin make a stray harmless.
- Suppressing a Stray Kernel from the GRUB menu entirely (a custom
  `grub.d` generator). The default-pin is sufficient; the stray remains
  a selectable entry.
- Full per-kernel preset/fallback/bootloader wiring for multiple
  selected kernels (still the Primary-Kernel bridge of ADR 0024).
- A two-stage reboot-survival VM test (a real post-upgrade reboot). The
  first-boot hook check covers the same regressions far more cheaply.

## Further Notes

- This depends on ADR 0024 for the Kernel Selection set and the reused
  `zfs.ko`-presence check, and on ADR 0023 for the single-source
  artifact pattern that keeps the installer and the retrofit tool from
  drifting.
- The two ESP hooks were previously easy to conflate; they are now
  distinct glossary terms — **ESP Kernel Sync** (ZFS `/boot` → primary
  ESP, systemd-boot only) and **ESP Mirror Hook** (primary ESP →
  secondary ESPs, multi-disk, bootloader-agnostic).
- The original incident: a 512M ESP + a stray `linux` + a glob-and-no-
  exit-check `cp` truncated the initramfs; the follow-on was a dangling
  `amd-ucode` initrd reference on an Intel board. Both classes are
  closed here.
