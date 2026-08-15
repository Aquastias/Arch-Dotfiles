# Bootloader expansion: five loaders, per-kernel entries, ESP auto-size, Abort

Status: ready-for-agent

Grows the Bootloader Module from two loaders to five, boots every selected
kernel instead of only the Primary Kernel, makes `esp_size` compute itself from
the Kernel Selection, and adds an explicit **Abort** terminal action to the
Guided Installer. See ADR 0077 (five loaders / ESP-mirroring taxonomy /
Bootloader Manifest / Abort), ADR 0078 (per-kernel entries / kernel-aware ESP
auto-size), amending ADR 0038 (ESP Kernel Sync, small-ESP sizing), and the
**Bootloader Adapter**, **ESP-mirroring loader**, **Bootloader Manifest**, and
**Abort** glossary terms in `CONTEXT.md`.

## Problem Statement

As an operator, I can only pick `systemd-boot` or `grub`, but I want `efistub`,
`limine`, and `refind` too. The installer also only ever registers a boot entry
for the **Primary Kernel**, so when I select several kernels the others are
installed but not bootable without hand-editing the loader. And I have been
bitten by the ESP filling up: when I select many kernels with their fallback
initramfs, a fixed ESP overflows and the machine bricks (the exact failure ADR
0038 was written to stop, now re-triggered by multi-kernel selection).
Separately, in the Guided Installer there is no obvious way to walk away without
installing — I have to know that Esc quits.

## Solution

`options.bootloader` becomes a closed set of five — `systemd-boot`, `grub`,
`efistub`, `limine`, `refind` (default `systemd-boot`). Four are **ESP-mirroring
loaders** that boot by reading the kernel the **ESP Kernel Sync** mirrors onto
the FAT32 ESP; `grub` stays the native-ZFS special case that reads `/boot`
directly. A single **Bootloader Manifest** table drives the per-loader EFI
loader path, packages, and ESP-entry style, replacing the hardcoded
`if grub/else systemd` chains.

Every Bootloader Adapter now boots **every** selected kernel: the explicit-entry
loaders (`systemd-boot`, `limine`, `efistub`) emit a default + fallback entry
per kernel with per-kbase filenames; `grub` and `refind` already enumerate
kernels natively and only need their default pinned to the Primary Kernel. All
loaders default-boot the Primary Kernel.

`esp_size` gains an `auto` default that computes upward from the Kernel
Selection and filesystem — sized to hold every selected kernel's images plus
ZFS-module overhead, transient sync headroom, and one kernel of growth slack,
never below ADR 0038's 2G floor. A pre-install ESP budget guard refuses (never
silently rewrites) a numeric `esp_size` pin that is too small for the selected
kernels, surfaced live in the Guided Kernels / Disks screens.

The Guided Installer gains **Abort** as a fourth terminal action beside Proceed
/ Save / Export — an Esc-equivalent, pre-destructive clean exit that makes
`install.sh` skip the back-end.

## User Stories

1. As an operator, I want to choose `systemd-boot` as my bootloader, so that I
   keep the current default behaviour.
2. As an operator, I want to choose `grub`, so that I get a native-ZFS-reading
   loader with a menu.
3. As an operator, I want to choose `efistub`, so that I boot the kernel
   directly through UEFI with no loader binary.
4. As an operator, I want to choose `limine`, so that I use a modern
   config-driven loader.
5. As an operator, I want to choose `refind`, so that I get an auto-detecting
   graphical loader.
6. As an operator, I want an unknown `options.bootloader` value in my Host
   Profile to be rejected at load with its path, so that a typo fails fast
   instead of at install time.
7. As an operator using the Guided Installer, I want the bootloader radiolist to
   list all five loaders, so that I can pick any of them interactively.
8. As an operator, I want the same five choices whether I author via a committed
   Host Profile or the Guided Installer, so that the two front-ends never drift.
9. As an operator on a ZFS root, I want `efistub`, `limine`, and `refind` to
   boot my machine, so that ZFS root is not limited to systemd-boot and grub.
10. As an operator on `grub`, I want a small ESP, so that I do not waste disk
    space on kernel copies grub does not need.
11. As an operator selecting multiple kernels, I want a boot entry for each one,
    so that I can boot any selected kernel, not only the Primary Kernel.
12. As an operator, I want the Primary Kernel to be the default boot entry on
    every loader, so that the machine boots my preferred kernel unattended.
13. As an operator, I want each selected kernel to have a fallback entry, so that
    I can recover a kernel whose default initramfs fails.
14. As an operator, I want a Stray Kernel (one pulled in outside Kernel
    Selection) to still get no boot entry and never reach the ESP, so that the
    ADR 0038 stray-kernel protection is preserved under multi-kernel.
15. As an operator on `grub` or `refind`, I want the loader to keep discovering
    installed kernels natively, so that multi-kernel works without hand-written
    entries.
16. As an operator on a multi-disk OS layout, I want each secondary ESP to carry
    the same per-kernel entries as the primary, so that any OS disk can boot any
    selected kernel if the primary disk fails.
17. As an operator on `efistub` with a multi-disk layout, I want the secondary
    UEFI entries to carry the kernel plus its initrd and cmdline load options,
    so that a self-contained loader binary is not assumed.
18. As an operator, I want the ESP to be sized automatically from the number of
    kernels I select and whether my root is ZFS, so that I never have to guess a
    safe `esp_size`.
19. As an operator selecting every available kernel with fallbacks, I want the
    ESP to be large enough to hold them all, so that I do not re-hit the
    ESP-overflow brick.
20. As an operator, I want ESP auto-sizing to only ever grow the ESP above the
    2G default, never shrink it, so that later kernel additions still fit.
21. As an operator who pins a specific `esp_size`, I want the installer to refuse
    loudly with an actionable message when my pin is too small for my selected
    kernels, so that my choice is honoured or rejected but never silently
    overwritten.
22. As an operator in the Guided Installer, I want the ESP-too-small conflict
    surfaced on the Kernels and Disks screens while I select, so that I see the
    problem before Proceed.
23. As an operator on `grub`, I want ESP auto-sizing to skip the per-kernel
    budget, so that my ESP stays small regardless of how many kernels I select.
24. As an operator in the Guided Installer, I want an explicit **Abort** action
    row, so that I can leave without installing without knowing the Esc
    shortcut.
25. As an operator, I want Abort to be pre-destructive, so that nothing on disk
    is touched and there is nothing to roll back.
26. As an operator, I want Abort to make `install.sh` skip the back-end cleanly,
    so that aborting is indistinguishable from never having started.
27. As a maintainer, I want adding a sixth loader to be one adapter file plus one
    Bootloader Manifest row, so that no new `if/elif` branch grows across
    `configure.sh`, the package resolver, or the package list.

## Implementation Decisions

- **Closed-set `options.bootloader`.** The legal set becomes `systemd-boot`,
  `grub`, `efistub`, `limine`, `refind`, sourced from
  `menu_enum_options options.bootloader` as the single source of truth shared by
  the Guided menu and profile-load validation. An unknown value aborts at load
  with its path, consistent with ADR 0036's closed schema.
- **Bootloader Manifest.** A new pure token table, `lib/boot/bootloaders.sh`,
  keys each loader to its EFI loader path, package set, ESP-entry style, and
  ZFS-support flag. Sourced host-side by the package resolver and package list,
  and staged into the chroot for the orchestrator. Replaces the hardcoded
  `if grub/else systemd` branches for the secondary-ESP loader path
  (`configure.sh`) and the bootloader packages (`resolver.sh`, `list.sh`).
- **ESP-mirroring taxonomy.** `systemd-boot`, `efistub`, `limine`, `refind`
  reuse the existing ESP Kernel Sync + ESP copy machinery unchanged; `grub` is
  the native-ZFS reader and installs no ESP Kernel Sync hook. Entry format and
  loader-binary path are the only per-loader differences, both carried by the
  manifest.
- **Per-loader entry formats.** `efistub` is raw (kernel + `initrd=` + cmdline as
  `efibootmgr` load-options), one entry per kernel + fallback; `refind` uses
  autodetect + `refind_linux.conf`; `limine` uses a generated `limine.conf`;
  `systemd-boot` keeps its loader-entry files. `grub` uses `grub-mkconfig`.
- **Multi-kernel entries.** Adapters iterate the ordered `KERNELS` array already
  present in install-state (element 0 = `KERNEL` = Primary Kernel). Explicit
  loaders emit per-kbase default + fallback entries (`arch-${KBASE}.conf` /
  `arch-${KBASE}-fallback.conf`, replacing the hardcoded `arch-zfs.conf`). Every
  loader pins its default selection to the Primary Kernel via its own mechanism.
  `grub`/`refind` keep native kernel discovery; only their default is pinned.
- **Shared efistub emit helper.** A single pure function renders an efistub
  entry (label, kernel loader path, `initrd=` + cmdline load-options) keyed off
  the manifest `esp_style`. Both the primary registration and the secondary-ESP
  loop call it, so cmdline / initrd / microcode never drift between disks and the
  entry count scales with `KERNELS`.
- **ESP Kernel Sync unchanged in mechanism.** It stays entry-driven, so once
  entries reference every selected kernel it mirrors them all; the Stray Kernel
  exclusion is preserved.
- **`esp_size: auto` (upward-only, estimate-based).** `esp_size` gains an `auto`
  mode that becomes the default and computes:
  `need = base (~180M) + Σ selected kernels × (vmlinuz ~16M + default initramfs
  ~54M + fallback initramfs ~205M + zfs surcharge ~30M when filesystem=zfs) +
  transient ~205M + one-kernel slack ~305M`, then `esp_size = max(2G,
  roundup_256M(need))`. Sizing happens at partition time, before any initramfs
  is built, so it is an estimate; ADR 0038's runtime PreTransaction preflight
  remains the truth-time backstop. `grub` is exempt (fixed small ESP, no
  per-kernel term).
- **Pre-install ESP budget guard.** A pure `esp_budget_need(kernels, fs, loader)`
  function feeds both profile-load validation and the Guided live Kernels / Disks
  checks. When a numeric `esp_size` pin is below `need` for an ESP-mirroring
  loader, the installer blocks with an actionable error (naming the shortfall
  and a suggested minimum). A pinned value is never silently auto-bumped.
- **Abort terminal action.** The Guided Installer gains a fourth terminal action
  row, Abort, alongside Proceed / Save / Export. It routes to the same clean
  cancel path Esc already triggers, so `guided_build` returns the cancel result
  and `install.sh` skips the back-end. Pre-destructive only; no mid-install
  rollback.
- **Roadmap boundaries recorded in ADRs.** UKI / secure-boot is out of scope
  (future cross-loader ADR); mid-install (destructive-phase) Abort with rollback
  is rejected.

## Testing Decisions

Good tests here assert **external behaviour of pure string-emitting lib
functions** — the emitted entry text, the resolved package list, the computed
ESP size, the enum contents, the presence of an action row — never internal
wiring. The chroot adapter shells and the real partitioning are covered by the
VM matrix, not unit tests. Prior art is the existing bats suite that sources a
lib and asserts on `run` output.

- **Bootloader Manifest** (`lib/boot/bootloaders.sh`): a new bats file
  (`packages/bootloaders.bats`) asserting each loader's EFI loader path, package
  set, ESP-entry style, and ZFS-support flag. Prior art: `packages/kernel.bats`,
  `tests/grub-common.bats`.
- **Entry-emit + efistub helper**: a new bats file over the pure entry renderers
  and the shared efistub emit helper — asserting per-kbase filenames, default +
  fallback entries for a multi-kernel selection, the Primary-Kernel default pin,
  and that efistub entries carry `initrd=` + cmdline load-options. Use the
  `LIB_ONLY` guard pattern so the chroot copy/register steps are skipped. Prior
  art: `tests/grub-common.bats`, `boot/esp-kernel-sync.bats`.
- **ESP budget** (`esp_budget_need` / `esp_size_auto`): a new bats file
  asserting the computed size across kernel counts and filesystems, the
  upward-only `max(2G, …)` floor, the ZFS surcharge, and the `grub` exemption.
  Prior art: `packages/kernel.bats`, `packages/microcode.bats`.
- **Enum SSOT**: extend `config/menu-enum.bats` to assert
  `menu_enum_options options.bootloader` lists all five.
- **Closed-set validation**: extend `config/profile-loader.bats` /
  `config/validation-*.bats` to assert an unknown loader is rejected with its
  path, and that the pre-install ESP guard rejects a too-small pin with an
  actionable message.
- **Package resolution**: extend `packages/resolver.bats` / `packages/packages.bats`
  to assert each loader resolves its manifest-declared packages (e.g. `refind`,
  `limine`; `efistub`/`systemd-boot` add none beyond `efibootmgr`).
- **Guided Abort + radiolist**: extend `config/guided-controller.bats` /
  `config/guided-menu.bats` to assert the Abort action row is emitted and maps to
  the cancel directive, and that the bootloader radiolist shows five options.
- **ESP Kernel Sync under multi-kernel**: extend `boot/esp-kernel-sync.bats` with
  cases proving entries referencing several kernels mirror all of them and still
  exclude a Stray Kernel.
- **VM matrix**: extend the `bootloader` axis in `lib/matrix/generator.sh` from
  `systemd-boot grub` to all five (pairwise-affecting, light) so each loader boots
  end-to-end in a VM.

## Out of Scope

- **UKI / secure-boot.** efistub ships raw (kernel + initrd + cmdline). UKI is a
  cross-loader signing/image concern and, when needed, becomes its own ADR — not
  bolted onto efistub.
- **Mid-install (destructive-phase) Abort with rollback.** Abort is
  pre-destructive only; the typed-`INSTALL` gate remains the last consent point.
- **Measuring the built initramfs to size the ESP.** Impossible by ordering; the
  budget is an estimate with the ADR 0038 runtime preflight as backstop.
- **Silently auto-bumping a pinned `esp_size`.** Too-small pins block; they are
  never rewritten.
- **Per-loader theming / cosmetic configuration** (refind themes, limine
  wallpapers, etc.).

## Further Notes

- Implementation TODO from the grilling: pin the real compressed
  `zfs.ko`-in-initramfs surcharge by measurement; ~30M/kernel is the working
  budget until then.
- Measured worst case (real Arch box, raw layout): ~275M/kernel (16M vmlinuz +
  54M default + 205M fallback initramfs); four ZFS kernels with fallbacks +
  transient + slack ≈ 1.9G → rounds to ~2G. The old 1G floor cannot hold the
  full set — the overflow class ADR 0038 exists to prevent.
- ADR 0078 amends ADR 0038 (lifts the primary-only entry rule; static 2G default
  → `auto`) and ADR 0077 (supersedes "keep primary-only"; makes the efistub
  secondary emit concrete). Respect both when touching this area.
- The five-way `bootloader` axis multiplies VM matrix cost; keep it
  pairwise-affecting/light per `lib/matrix/registry.sh` rather than fully
  crossing it with every other axis.
