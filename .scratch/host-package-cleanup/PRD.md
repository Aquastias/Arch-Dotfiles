# PRD: Host package dedup and Host Core package eviction

Status: ready-for-agent
Category: refactor

## Problem Statement

The operator recently grew `hosts/core/config.jsonc` (Host Core) into a
large Host Package List meant as a "universal base". That move
contradicts the documented model: ADR 0007 and the CONTEXT.md glossary
both say a Host Package List lives in a host-specific Host Config, **not**
in Host Core; Host Core carries only users, System Programs, and Sysctl
Defaults.

On top of that, the Host Configs (core, desktop, laptop) re-declare many
packages that an essentials script already installs, so the same package
is named in two places and the two drift:

- The **Base Package List** (`lib/packages.sh:collect_packages`) already
  pacstraps `base`, `base-devel`, the kernel + headers, `linux-firmware`,
  `intel-ucode`/`amd-ucode`, `networkmanager`, `openssh`, `efibootmgr`,
  `dosfstools`, `vim`, `git`, `sudo`, `rsync`, `jq`, `pacman-contrib`,
  `man-db`, … onto every host. The Host Configs list many of these again.
- The **GRUB Bootloader Adapter** installs `grub` + `os-prober` whenever
  `options.bootloader=grub`. The desktop Host Config lists both again.
- `paru` is bootstrapped from source by the Runner before any AUR pass,
  yet it is also declared in `packages.aur`.
- The `apparmor`/`clamav`/`rkhunter` **User Programs** (already declared
  for the `aquastias` user) install those tools fully configured via
  paru, plus their companions `unhide` and `clamav-unofficial-sigs` —
  all of which are *also* listed as bare packages in the Host Configs.

Three further defects:

- `system_programs` in the edited Host Core held `base`, `base-devel`,
  `cronie`, `parallel`. None resolve to a Program with `system: true`, so
  the System Program contract check in `validate_program` would abort the
  install.
- `cronie` is declared as a bare package but enabled nowhere, so cron is
  silently dead on every host.
- The `hyprland` package category sits in Host Configs, violating ADR
  0021 ("the Desktop Environment Adapter owns every package derivable
  from `environment.desktop`"). `kimageformats5` is duplicated between a
  Host Config and the KDE adapter's `apps_list`. `timeshift` is listed
  but supports only btrfs/rsync, not the ZFS root this installer builds.

## Solution

Make the **Base Package List** the single shared package base and keep
Host Core free of any Host Package List, per ADR 0007. Everything an
essentials script already installs is removed from the Host Configs.

- **Host Core** keeps `users`, `system_programs: ["cups"]`, and `sysctl`
  only — its `packages` object is deleted.
- **cronie** is reclassified as universal infrastructure (ADR 0026):
  added to the Base Package List and enabled in the Chroot Configuration
  Module next to NetworkManager/resolved/timesyncd, and removed from all
  Host Configs.
- **desktop/laptop Host Configs** drop every Base-Package-List duplicate,
  the GRUB adapter packages (`grub`, `os-prober`), the bootstrapped
  `paru`, the User-Program-owned `apparmor`/`clamav`/`rkhunter` plus their
  companions `unhide` and `clamav-unofficial-sigs`, the ZFS-incompatible
  `timeshift`, the KDE-adapter-owned `kimageformats5`, and the pure
  makedepend `extra-cmake-modules`. `parallel` (evicted from core) is
  added to them. Residual general packages are regrouped into an
  accurately named `desktop` Categorized List category.
- **The Hyprland Desktop Environment Adapter** absorbs the DE-derivable
  Hyprland packages (ADR 0021 amendment). General, DE-agnostic packages
  stay in the Host Configs; `xorg-xinit` is dropped (pure-Wayland
  session).

The supporting decisions are already recorded in the repo: ADR 0021 was
amended, ADR 0026 was created, and CONTEXT.md gained the Base Package
List term plus a Flagged ambiguities note. This PRD covers the code and
config changes that those decisions imply.

## User Stories

1. As the installer operator, I want Host Core to declare no Host Package
   List, so that the config matches the documented model (ADR 0007) and a
   reader is not misled about where packages live.
2. As a future maintainer, I want the Base Package List to be the one
   shared package base, so that I know exactly one place holds packages
   every host receives.
3. As the operator, I want `cronie` installed by the Base Package List, so
   that every host — including a server or VM — gets cron without
   per-host declaration.
4. As the operator, I want `cronie.service` enabled in the Chroot
   Configuration Module, so that cron actually runs after first boot
   instead of being installed-but-dead.
5. As a future maintainer, I want cron to follow the NetworkManager
   pattern rather than the cups System Program pattern, so that universal
   infrastructure is not mistaken for an optional feature (ADR 0026).
6. As the operator, I want `base`, `base-devel`, `networkmanager`, `vim`,
   `git`, `efibootmgr`, `linux-firmware`, `man-db`, `dosfstools`, `jq`,
   and the microcode packages removed from Host Configs, so that the
   Base Package List is the sole declaration of each.
7. As the operator, I want `grub` and `os-prober` removed from the
   desktop Host Config, so that the GRUB Bootloader Adapter remains their
   only installer and a systemd-boot host does not pull an unused
   bootloader.
8. As the operator, I want the desktop host to keep `grub` in
   `system_programs` if it uses GRUB, so that the declarative bootloader
   path is unchanged while the duplicate package entry is gone.
9. As the operator, I want `paru` removed from `packages.aur`, so that the
   package that the Runner bootstraps from source is not redundantly
   redeclared.
10. As the operator, I want `apparmor`, `clamav`, and `rkhunter` removed
    from Host Config packages, so that their fully-configured User
    Programs are the single source of truth.
11. As the operator, I want `unhide` and `clamav-unofficial-sigs` removed
    from Host Configs, so that the rkhunter and clamav User Programs
    remain their only installer.
12. As the operator, I want `timeshift` removed, so that I am not carrying
    a backup tool that cannot operate on a ZFS root when ZFS snapshots,
    Impermanence, and the backup Programs already cover that need.
13. As the operator, I want `extra-cmake-modules` dropped entirely, so
    that a pure makedepend that paru resolves at build time is not
    permanently installed or mis-located in Host Core.
14. As the operator, I want `kimageformats5` removed from Host Configs, so
    that the KDE adapter's `apps_list` is its only declaration (ADR 0021).
15. As the operator, I want `qt5-wayland` and `qt6-wayland` kept in the
    Host Configs, so that Qt applications render natively on Wayland under
    Hyprland (where they are not pulled transitively).
16. As the operator, I want the `parallel` package moved from Host Core
    into the desktop/laptop Host Configs, so that it stays available where
    it is wanted without living in Host Core.
17. As the operator, I want the leftover general packages grouped under a
    `desktop` Categorized List category, so that the category name matches
    its contents instead of the stale `qt-and-kde`/`hyprland` names.
18. As the operator, I want the Hyprland Desktop Environment Adapter to
    install `hyprland`, `xdg-desktop-portal-hyprland`,
    `xdg-desktop-portal-gtk`, and `wl-clipboard` as its non-negotiable
    core, so that a working Hyprland session does not depend on Host
    Config entries.
19. As the operator, I want `dunst`, `wofi`, `grim`+`slurp`, and
    `nwg-look` exposed as Hyprland adapter companion toggles, so that I
    can deselect any of them from `install-hyprland.jsonc` without editing
    shell.
20. As the operator, I want `wofi` available as a launcher toggle, so that
    the adapter reflects the launcher I actually use rather than only its
    `fuzzel`/`rofi` defaults.
21. As the operator, I want `xdg-utils` and `papirus-icon-theme` to stay
    in the Host Configs, so that DE-agnostic desktop packages are not
    forced into a single DE adapter.
22. As the operator, I want `xorg-xinit` dropped, so that a pure-Wayland
    Hyprland setup with no `.xinitrc` does not carry an X11 session
    launcher.
23. As an AFK agent, I want the System Programs in every Host Config to
    pass the `validate_program` contract, so that the install does not
    abort during program preflight.
24. As an AFK agent, I want the `vm` Host Config to remain empty, so that a
    test VM inherits only the Base Package List, `cups`, and Sysctl
    Defaults — a minimal headless install.
25. As an AFK agent, I want `collect_packages` to keep emitting a
    sorted-unique list after `cronie` is added, so that pacstrap input
    stays deduplicated.
26. As a future maintainer, I want bats coverage proving `cronie` is in
    the collected base set, so that a later edit cannot silently drop it.
27. As a future maintainer, I want bats coverage proving `cronie.service`
    is enabled by the Chroot Configuration Module, so that the
    install-but-dead-cron regression cannot return.
28. As a future maintainer, I want bats coverage proving the Hyprland
    adapter resolves the expected package set from its toggles, so that
    the migration is locked against drift.
29. As a future maintainer, I want bats coverage proving Host Core merges
    cleanly with a host config when Host Core has no `packages` object, so
    that the ADR-0007 shape is enforced.
30. As the operator, I want the changes confined to the listed five
    modules, so that the cleanup does not bleed into unrelated installer
    phases.

## Implementation Decisions

- **Five modules are touched, no new deep module is introduced.** The
  work rides existing seams.
- **Base Package List** (`lib/packages.sh:collect_packages`): add
  `cronie` to the hardcoded base array. Output stays sorted-unique.
- **Chroot Configuration Module** (`lib/chroot/configure.sh`): add
  `systemctl enable cronie` alongside the existing NetworkManager,
  systemd-resolved, and systemd-timesyncd enables. Per ADR 0026, cron is
  universal infrastructure, not a System Program.
- **Host Core** (`hosts/core/config.jsonc`): delete the entire `packages`
  object. Retain `users`, `system_programs: ["cups"]`, and `sysctl`.
  `cups` stays because System Programs are permitted in Host Core (ADR
  0004/0021); only the Host Package List is evicted.
- **Host Configs** (`hosts/desktop`, `hosts/laptop`): remove every entry
  an essentials script already provides — Base Package List duplicates,
  GRUB adapter packages (`grub`, `os-prober`, desktop only),
  bootstrapped `paru`, User-Program-owned `apparmor`/`clamav`/`rkhunter`
  with `unhide` and `clamav-unofficial-sigs`. Remove `timeshift`,
  `kimageformats5`, and `extra-cmake-modules`. Add `parallel`. The
  desktop host keeps `system_programs: ["grub"]` (declarative bootloader
  path) but not the `grub`/`os-prober` packages.
- **Category reorganization**: the residual general packages
  (`qt5-wayland`, `qt6-wayland`, `xdg-utils`, `papirus-icon-theme`) move
  into a single `desktop` category in the `packages.repo` Categorized
  List. Categories are cosmetic, so this is a readability change only.
- **Hyprland Desktop Environment Adapter** (`extras/desktop/hyprland/`):
  the adapter's hardcoded core gains `wl-clipboard` and
  `xdg-desktop-portal-gtk`; `install-hyprland.jsonc` gains companion
  toggles `screenshot` (installs `grim` + `slurp`), `gtk-look` (installs
  `nwg-look`), and `wofi` (launcher). DE-agnostic packages remain in the
  Host Configs; `xorg-xinit` is not carried by the adapter.
- **No User Config or Stow change**: `users/aquastias` already declares
  the `apparmor`/`clamav`/`rkhunter` User Programs; nothing about user
  provisioning changes.

## Testing Decisions

A good test asserts external behavior — the package set a module
resolves, the services it enables, the merge result of two configs — not
the internal control flow that produces them. Tests should survive a
refactor that keeps behavior identical.

Tests are written for four modules, each with direct bats prior art:

- **Base Package List** — extend `tests/packages.bats`: assert `cronie`
  appears in the `collect_packages` output and that the list remains
  sorted and deduplicated. Prior art: existing `packages.bats` cases that
  assert membership and dedup of the collected list.
- **Chroot Configuration Module** — extend `tests/chroot-configure.bats`:
  assert `cronie.service` is enabled, alongside the existing assertions
  for NetworkManager/resolved/timesyncd.
- **Hyprland Desktop Environment Adapter** — extend
  `tests/hyprland-adapter.bats`: assert the core set includes
  `wl-clipboard` and `xdg-desktop-portal-gtk`, and that the new
  `screenshot`/`gtk-look`/`wofi` toggles resolve to the expected packages
  when on and contribute nothing when off. Prior art: existing
  `hyprland-adapter.bats` and the `kde-adapter.bats` toggle-resolution
  pattern.
- **Host Configs** — extend `tests/configs.bats`: assert Host Core merges
  with a host config when Host Core carries no `packages` object, and
  that the host `packages.repo` Categorized List (including the new
  `desktop` category) parses. Prior art: `configs.bats` merge cases and
  `parse-categorized.bats`.

## Out of Scope

- The sops machinery: `sops`/`age` are governed by ADR 0025
  (secrets-activated sops Program) and the secrets-activated-sops work;
  this PRD only removes any stray `sops`/`age` package entries from Host
  Configs.
- KDE adapter changes beyond noting that `kimageformats5` is already
  owned by its `apps_list`.
- The deeper Hyprland refactor into a pure toggles→package-set resolver
  (mirroring KDE's `categorized_list_parse`). Flagged as a latent
  deepening; not done here.
- The `vm` Host Config and `users/aquastias` User Config — unchanged.
- Running an actual machine install; verification is via bats plus the
  existing VM smoke harness, not a fresh metal install.

## Further Notes

- Decisions originate from a grill-with-docs session; the doc artifacts
  (CONTEXT.md Base Package List term + Flagged ambiguities, ADR 0021
  amendment, ADR 0026) are already committed and should be treated as the
  spec of record where this PRD and they overlap.
- The same dedup logic applies in principle to any future Host Config;
  this pass cleans `core`, `desktop`, and `laptop`.
- After this change, adding a package every host needs is a Base Package
  List edit (code); adding a host-specific package is a Host Config edit;
  adding a DE package is a Desktop Environment Adapter edit. Three
  distinct homes, no overlap.
