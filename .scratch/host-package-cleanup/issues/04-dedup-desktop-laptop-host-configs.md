# Dedup desktop + laptop Host Configs

Status: ready-for-agent

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

- [ ] desktop + laptop configs contain none of the removed packages above.
- [ ] desktop retains `system_programs: ["grub"]`; no `grub`/`os-prober`
      in its `packages`.
- [ ] `parallel` is present in both; `qt5/qt6-wayland`, `xdg-utils`,
      `papirus-icon-theme` retained; `xorg-xinit` absent.
- [ ] Residual general packages live under a `desktop` category; no
      `qt-and-kde`/`hyprland` categories remain.
- [ ] The `packages.repo` Categorized List parses (no shape/leaf/category
      violation).
- [ ] `configs.bats` covers host-repo dedup vs the Base Package List and
      parsing of the new `desktop` category.

## Blocked by

- `.scratch/host-package-cleanup/issues/02-cronie-universal-infrastructure.md`
  (cronie must be in the Base Package List before it is removed here)
- `.scratch/host-package-cleanup/issues/03-hyprland-adapter-absorbs-de-packages.md`
  (the adapter must own the Hyprland packages before they are removed here)
