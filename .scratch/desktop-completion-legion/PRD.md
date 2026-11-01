# Desktop completion: hybrid Legion laptop + wlroots sessions

Status: ready-for-agent

Decisions of record: ADR 0161 (hybrid laptop completion, Legion 5
15ARH7H; amends ADR 0053) and ADR 0162 (niri runs XDG autostart;
wlroots sessions completion; amends ADR 0131, ADR 0080). Builds on
ADR 0097/ADR 0100 (Wayland Shell Companion owns lock/idle/polkit),
ADR 0114/ADR 0157 (Fleet Layer), ADR 0149 (AUR vetting).

Glossary (`CONTEXT.md`): Fleet Layer, Host Program, Desktop Environment
Adapter, Wayland Shell Companion, Package Resolver, GPU Resolution, GPU
Hardening, Hybrid Graphics / PRIME Offload, Feature Audit, Audit Run,
Fleet Golden. No new terms.

## Problem Statement

The operator runs two fleet hosts: `eterniox` (AMD desktop) and `chronos`
(Lenovo Legion 5 15ARH7H — Ryzen 5 6600H iGPU + RTX 3060 dGPU, 16 GB RAM).
Both offer Umbriel, KDE, niri and Hyprland. After a fresh install the
wlroots sessions and the laptop are close to, but not quite, a finished
daily driver:

- On the laptop, `prime-run` does not exist, so offloading a game to the
  RTX 3060 means hand-setting PRIME env vars; Dynamic Boost is off; 32-bit
  Vulkan games only see the dGPU; fans, CPU temperature and Fn+Q modes have
  no Legion tooling; ZFS ARC competes with games for 16 GB.
- In niri, KDE's background apps (kalendarac → akonadi, kdeconnectd) and
  nm-applet start beside Noctalia, wasting memory, duplicating trays and
  logging portal errors.
- "Show in folder" from a browser opens Dolphin, while `Super+E` opens
  pcmanfm-qt.
- pcmanfm-qt cannot see an Android phone and shows no video thumbnails.
- niri's Secret portal points at gnome-keyring, which is not installed.
- Hyprland alone has a blueman tray beside Noctalia's Bluetooth panel.
- wireplumber logs a missing UPower on the desktop.
- A wlroots-only box (no KDE) would lose Qt-on-Wayland.
- Nothing intervenes before the kernel OOM killer on memory exhaustion.

## Solution

One pass that closes every gap, largest first, each its own commit:

1. Hybrid machines get `prime-run` and Dynamic Boost.
2. Every AMD host gets 32-bit AMD Vulkan explicitly.
3. The laptop gets LenovoLegionLinux (module + tools, `legiond` off).
4. The laptop caps ZFS ARC at 4 GiB through a new profile option.
5. niri stops starting KDE background apps and nm-applet (KDE co-install).
6. pcmanfm-qt runs as a daemon in every wlroots session and answers
   "Show in folder".
7. niri's Secret portal resolves to kwallet (KDE co-install).
8. Fleet hosts get systemd-oomd acting on swap exhaustion and user-session
   memory pressure.
9. The Wayland Shell Companion preset gains `gvfs-mtp`,
   `ffmpegthumbnailer`, `upower` and `qt6-wayland`.
10. Hyprland drops blueman; Noctalia is the one Bluetooth UI everywhere.

The laptop's BIOS stays in hybrid mode; discrete (MUX) mode is
documented as unsupported.

## User Stories

1. As the laptop operator, I want `prime-run <app>` to work after install,
   so that I can run a game on the RTX 3060 without hand-set env vars.
2. As the laptop operator, I want `prime-run glxinfo` to report the NVIDIA
   renderer, so that I can confirm offload works.
3. As the laptop operator, I want `nvidia-powerd` enabled, so that the
   RTX 3060 gets its Dynamic Boost power budget in games.
4. As the laptop operator, I want `nvidia-smi -q` to show the boosted
   power limit, so that I can verify Dynamic Boost is active.
5. As a desktop operator with only an NVIDIA card, I want neither
   `nvidia-prime` nor `nvidia-powerd`, so that no laptop-only service runs
   or errors on my machine.
6. As an AMD host operator, I want `lib32-vulkan-radeon` installed
   explicitly, so that 32-bit Vulkan games run on the AMD GPU by design,
   not by provider luck.
7. As the laptop operator, I want 32-bit Vulkan to see the iGPU too, so
   that 32-bit games do not force the dGPU awake.
8. As an operator with multilib off, I want `lib32-vulkan-radeon` dropped
   automatically, so that pacstrap never fails on a missing repo.
9. As the laptop operator, I want LenovoLegionLinux installed, so that I
   can read CPU temperature and set fan curves.
10. As the laptop operator, I want `legiond` left disabled, so that
    power-profiles-daemon stays the sole owner of the power profile.
11. As the laptop operator, I want LenovoLegionLinux to be a laptop-only
    Host Program, so that the desktop never builds a Legion kernel module.
12. As the maintainer, I want LenovoLegionLinux's AUR packages vetted like
    every other AUR package, so that an unreviewed PKGBUILD never runs.
13. As the laptop operator, I want ZFS ARC capped at 4 GiB, so that games
    keep the memory they need.
14. As the desktop operator, I want ARC left at the ZFS default, so that
    the desktop's larger RAM still caches freely.
15. As a profile author, I want the ARC cap as a profile option with no
    default, so that a host opts in deliberately.
16. As a Guided Installer user, I want no new ARC menu row, so that the
    menu stays lean for a rarely-needed knob.
17. As a niri user on a KDE co-install, I want kalendarac, kdeconnectd,
    nm-applet and the Discover notifier not to start, so that only
    Noctalia's UI is present.
18. As a KDE user, I want those same apps to keep autostarting in Plasma,
    so that suppression in niri never changes KDE.
19. As a niri user, I want `pam_kwallet_init`, at-spi and `xdg-user-dirs`
    to keep running, so that the wallet unlocks and accessibility works.
20. As the maintainer, I want suppression to survive package upgrades, so
    that a KDE update never brings the leak back.
21. As a niri user without KDE, I want nothing written, so that a bare
    niri box stays bare.
22. As a wlroots user, I want "Show in folder" in a browser to open
    pcmanfm-qt, so that one file manager is used across the session.
23. As a KDE user, I want "Show in folder" to keep opening Dolphin in
    Plasma, so that Plasma behaviour is unchanged.
24. As a wlroots user, I want `Super+E` to keep opening pcmanfm-qt
    windows, so that the daemon does not change the bind.
25. As a niri user on a KDE co-install, I want the Secret portal to use
    kwallet, so that sandboxed apps can store secrets.
26. As a niri user without KDE, I want the packaged portal config kept,
    so that no kwallet route points at a missing service.
27. As a fleet operator, I want systemd-oomd to act before the kernel OOM
    killer, so that a runaway app is killed instead of the desktop freezing.
28. As a fleet operator, I want oomd to watch swap exhaustion and user
    session memory pressure, so that it actually acts (Arch ships no
    defaults).
29. As a non-fleet installer user, I want no oomd, so that the neutral
    Host Core stays neutral.
30. As a wlroots user, I want my Android phone to appear in pcmanfm-qt,
    so that I can copy files over USB.
31. As a wlroots user, I want video thumbnails in pcmanfm-qt, so that I
    can find videos by sight.
32. As a wlroots user, I want UPower always available, so that peripheral
    batteries show and wireplumber stops logging errors.
33. As a wlroots-only operator (no KDE), I want `qt6-wayland`, so that Qt
    apps (pcmanfm-qt, qt6ct) run natively on Wayland.
34. As a Hyprland user, I want no blueman tray, so that Bluetooth is
    managed only through Noctalia, as on niri and Umbriel.
35. As the maintainer, I want the Package Resolver to report every new
    package, so that query and install never drift.
36. As the maintainer, I want the Fleet Golden fixtures regenerated only
    for these deliberate changes, so that an unrelated diff still fails.
37. As the maintainer, I want the desktop/laptop parity check to exempt
    laptop-only hardware Host Programs, so that ADR 0114 still guards the
    shared software image.
38. As the maintainer, I want the desktop Feature Audit to prove the niri
    leak is gone, so that a regression is caught in the VM.
39. As the maintainer, I want the Feature Audit to prove FileManager1 is
    owned by pcmanfm-qt in each wlroots session, so that the Dolphin
    hijack cannot return silently.
40. As the maintainer, I want the Feature Audit to prove oomd monitors the
    configured cgroups, so that a silent no-op oomd is caught.
41. As the laptop operator, I want an on-Legion checklist, so that the
    hardware-only items are verified the same way every time.
42. As the laptop operator, I want the checklist to verify niri and
    Umbriel drive the iGPU, so that an iGPU pin is added only if needed.
43. As the laptop operator, I want discrete BIOS mode documented as
    unsupported, so that a black screen after flipping it is not a mystery.

## Implementation Decisions

- **GPU Resolution**: the AMD vendor map gains `lib32-vulkan-radeon`. The
  existing multilib filter already strips `lib32-*` when multilib is off.
- **GPU Hardening** (the chroot GPU Configuration Module, amd+nvidia gate):
  - installs `nvidia-prime` and enables `nvidia-powerd.service` alongside
    the existing suspend/resume/hibernate services;
  - the gate is unchanged: single-vendor, VM or intel is still a no-op.
  - The Package Resolver cannot see `gpu=auto` vendors (resolved by lspci
    at install), so these are covered at the module seam, not the golden.
- **LenovoLegionLinux Host Program** (`system` category): installs
  `lenovolegionlinux-dkms-git` and `lenovolegionlinux-git` through the
  vetted paru pass; enables no service (`legiond` stays off). Declared in
  the laptop profile's `host_programs` only. Both packages go through AUR
  vetting before first install. Grounded on the Arch Wiki Laptop/Lenovo
  and Fan speed control pages plus upstream's confirmed-model list.
- **ZFS ARC cap**: a new schema row `options.zfs.arc_max` (scalar, default
  empty = ZFS default), profile-only (no Guided row). When set, the chroot
  writes `options zfs zfs_arc_max=<bytes>` to the ZFS modprobe config;
  the value accepts a size suffix (`4G`) converted to bytes. The laptop
  profile sets `4G`.
- **niri autostart suppression** (niri Desktop Environment Adapter, only
  when `kde` is in the resolved desktop set): for each blocklisted
  autostart id, a systemd user drop-in for the generated
  `app-<id>@autostart.service` carrying
  `ConditionEnvironment=!XDG_CURRENT_DESKTOP=niri`. The blocklist is one
  list in the adapter: kalendarac, the kdeconnect daemon, nm-applet, the
  Discover notifier (exact ids confirmed from the VM's autostart dir).
- **pcmanfm-qt daemon**: each compositor's curated autostart (niri
  `conf.d/autostart`, Hyprland `conf.d/autostart`, Umbriel
  `conf.d/autostart`) starts `pcmanfm-qt -d`, beside the existing Noctalia
  and Live Theme Bridge entries. No D-Bus service file.
- **niri Secret portal** (niri adapter, KDE co-install only): an
  `/etc/xdg-desktop-portal/niri-portals.conf` that keeps the packaged
  preferences and routes `org.freedesktop.impl.portal.Secret=kwallet`.
- **systemd-oomd Host Program** (`system` category), declared in the Fleet
  Layer's `host_programs`: enables `systemd-oomd.service` and ships two
  drop-ins mirroring Fedora's `systemd-oomd-defaults` —
  `-.slice` → `ManagedOOMSwap=kill`; `user@.service` →
  `ManagedOOMMemoryPressure=kill`, `ManagedOOMMemoryPressureLimit=50%`.
  Grounded on `systemd-oomd(8)` / `systemd.resource-control(5)`; the Arch
  Wiki has no config section (Improving performance only lists it), which
  the program spec records.
- **Wayland Shell Companion preset**: `noctalia_preset_packages` gains
  `gvfs-mtp`, `ffmpegthumbnailer`, `upower`, `qt6-wayland`. All
  package-only or D-Bus activated (no service enable).
- **Hyprland adapter**: the blueman section (install + autostart
  overwrite) is removed.
- **Fleet Golden**: desktop and laptop fixtures regenerated once per
  change that alters them; the parity test compares the two sets with
  laptop-only hardware Host Programs excluded (ADR 0161).
- **Docs**: ADR 0161/ADR 0162 are already written; `CONTEXT.md`
  Hybrid Graphics entry notes `prime-run` and Dynamic Boost; the on-Legion
  checklist is extended.

## Testing Decisions

A good test asserts what the install produces — package lists, written
files, enabled units — through the highest existing seam, never the
internals of how a helper builds them. All seams already exist:

- **Fleet Golden** (`fleet-golden.bats`): preset package additions, both
  new Host Programs, the `arc_max` schema row. Prior art: the Fleet Layer
  split (ADR 0157).
- **GPU Resolution** (`gpu-resolution.bats`) and **GPU Hardening**
  (`chroot-gpu.bats`): `lib32-vulkan-radeon` in the AMD map and dropped
  with multilib off; `nvidia-prime` + `nvidia-powerd` on amd+nvidia only,
  absent on single-vendor/VM. Prior art: ADR 0053's gate tests.
- **Desktop Environment Adapter bats** (`niri-adapter.bats`,
  `hyprland-adapter.bats`, `ROOT` seam): drop-ins and portal override
  written iff KDE co-installed; nothing on bare niri; blueman gone.
- **Curated-config stow bats** (`noctalia-stow-config.bats`,
  `umbriel-stow-config.bats`): `pcmanfm-qt -d` present in all three
  autostarts. Prior art: ADR 0131's xdg-dirs autostart test.
- **Program bats** (`*-program.bats`): oomd drop-in content + service;
  LenovoLegionLinux packages and no `legiond` enable.
- **ZFS** chroot bats: `zfs_arc_max` written with bytes when set, nothing
  when unset.
- **Feature Audit** (desktop variant, VM): niri session has no kalendarac
  / kdeconnectd / nm-applet process; FileManager1 owner is pcmanfm-qt in
  niri, Hyprland and Umbriel; niri Secret portal resolves to kwallet;
  `oomctl` lists `-.slice` and `user@.service`. Prior art: the ADR 0100
  polkit prober.
- **On-Legion checklist** (manual, not VM-verifiable): `prime-run
  glxinfo`, `nvidia-smi -q` Dynamic Boost, LLL sensors + fan curve,
  `arc_max` applied, brightness keys, battery conservation through
  Noctalia's plugin, niri/Umbriel on the iGPU.

## Out of Scope

- Keyboard RGB tooling (no confirmed tool for the 15ARH7H 4-zone board).
- Wi-Fi power-save tuning (chip unconfirmed).
- Detecting or supporting discrete (MUX) BIOS mode.
- iGPU pinning for niri/Umbriel unless the on-Legion check fails.
- A Guided Installer row for the ARC cap.
- earlyoom or any other OOM daemon.
- Intel GPU Vulkan (no Intel host in the fleet).

## Further Notes

- Order of work (largest impact first): `nvidia-prime` → `nvidia-powerd` →
  `lib32-vulkan-radeon` → LenovoLegionLinux → ARC cap → niri autostart
  suppression → pcmanfm-qt daemon → niri Secret portal → systemd-oomd →
  preset packages → blueman removal → checklist + `CONTEXT.md`.
- LenovoLegionLinux is `-git` DKMS against the LTS kernel; a kernel bump
  can break the build. Accepted in ADR 0161.
- `lenovolegionlinux-git` installs units under `/etc/systemd/system`; none
  are enabled.
- VM verification follows the one-VM-at-a-time rule (ADR 0155).

