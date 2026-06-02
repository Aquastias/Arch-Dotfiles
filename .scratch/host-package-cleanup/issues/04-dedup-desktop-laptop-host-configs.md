# Dedup desktop + laptop Host Configs

Status: done

## Parent

`.scratch/host-package-cleanup/PRD.md`

## What to build

Strip from the desktop and laptop Host Configs every package that an
essentials script, a Bootloader Adapter, the paru bootstrap, a Desktop
Environment Adapter, or a User Program already installs — leaving only
host-specific, non-duplicated declarations. The effective installed set is
unchanged; only the redundant declarations go.

Remove:

- Base Package List duplicates: `base`, `base-devel`, `amd-ucode`,
  `efibootmgr`, `linux-firmware`, `man-db`, `dosfstools`, `networkmanager`,
  `jq`, `vim`, `git`, and `cronie`.
- GRUB Bootloader Adapter packages `grub` and `os-prober` (desktop only).
  Keep desktop's `system_programs: ["grub"]` — only the package entries go.
- The bootstrapped `paru` from `packages.aur`.
- User-Program-owned `apparmor`, `clamav`, `rkhunter`, plus their
  companions `unhide` and `clamav-unofficial-sigs`.
- `timeshift` (ZFS-incompatible), `kimageformats5` (KDE adapter `apps_list`
  owns it), `extra-cmake-modules` (makedepend), and the Hyprland packages
  now owned by the adapter.

Then: add `parallel` to both configs; keep `qt5-wayland`/`qt6-wayland`,
`xdg-utils`, `papirus-icon-theme`; drop `xorg-xinit`; and regroup the
residual general packages into a single accurately-named `desktop`
Categorized List category (replacing the now-stale `qt-and-kde` and
`hyprland` categories).

## Acceptance criteria

- [x] desktop + laptop configs contain none of the removed packages above.
- [x] desktop retains `system_programs: ["grub"]`; no `grub`/`os-prober`
      in its `packages`.
- [x] `parallel` is present in both; `qt5/qt6-wayland`, `xdg-utils`,
      `papirus-icon-theme` retained; `xorg-xinit` absent.
- [x] Residual general packages live under a `desktop` category; no
      `qt-and-kde`/`hyprland` categories remain.
- [x] The `packages.repo` Categorized List parses (no shape/leaf/category
      violation).
- [x] `configs.bats` covers host-repo dedup vs the Base Package List and
      parsing of the new `desktop` category.

## Blocked by

- `.scratch/host-package-cleanup/issues/02-cronie-universal-infrastructure.md`
  (cronie must be in the Base Package List before it is removed here)
- `.scratch/host-package-cleanup/issues/03-hyprland-adapter-absorbs-de-packages.md`
  (the adapter must own the Hyprland packages before they are removed here)

## Comments

- Done (TDD). desktop + laptop `packages.repo` stripped of every Base /
  Bootloader-adapter / paru-bootstrap / DE-adapter / User-Program package;
  `qt-and-kde` + `hyprland` categories collapsed into one `desktop`
  category (desktop: papirus/qt5/qt6-wayland/xdg-utils; laptop:
  qt5-wayland/xdg-utils); `xorg-xinit` dropped; `parallel` added to both;
  `paru` + `clamav-unofficial-sigs` dropped from `packages.aur`.
- Also dropped stray `sops`/`age` (ADR 0025 secrets-activated-sops Program
  owns them) per the PRD Out-of-Scope note — the `security` category is
  gone from both hosts.
- Tests: +8 `configs.bats` real-config guards (no-duplicates, parallel +
  retained pkgs, `desktop` category present / `qt-and-kde`+`hyprland`
  gone, aur drops, no sops/age, desktop `system_programs:["grub"]` with no
  grub/os-prober pkg, repos parse). Full suite 722 green, shellcheck
  clean, `audit.sh` 81/81 (all packages resolve in repos/AUR).
