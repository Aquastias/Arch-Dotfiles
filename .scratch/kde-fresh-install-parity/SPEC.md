# Spec: Fresh KDE install matches the `arch-combined` reference box

Status: ready-for-agent

Related ADRs: 0110 (resolution autodetected), 0111 (KDE adapter seeds captured
Plasma settings), 0112 (stock/pure KDE skips the look), **0118** (timezone
autodetect), **0119** (VM Full-HD virtual panel), **0120** (capture set extended
+ packaged weather widget), **0121** (first-login state beyond captured config).

## Problem Statement

The operator built a complete Plasma setup on the `arch-combined` reference box,
but a fresh install does **not** come up looking like it. On first KDE login the
operator hits the Plasma Welcome Center; the timezone is `UTC` instead of their
real zone; night light never actually shifts; sound line in/out is not at 100%;
a VM comes up below Full HD; the screen reader is dead (Orca absent); KDE has no
printer support surfaced; the default video player is not VLC; Activities,
saved power profile, per-widget settings, the Activity Pager, favorites, the
chosen avatar and display name, and the login/lock wallpaper are all missing;
and the panel weather widget cannot find the operator's town (Râmnicu Vâlcea).

The root cause is that the **Captured Plasma Settings** vendored in the KDE
adapter are a stale snapshot that omits several config files, plus a set of
settings that cannot live in a captured `.config` file at all (**First-Login
State**), plus a few missing packages and one wrong **Host Profile** value.

## Solution

Re-capture the operator's live `arch-combined` `~/.config` into the KDE adapter's
vendored skel and **extend** the captured set, so a fresh KDE login lands on the
full setup with no first-run wizard. Seed the pieces that cannot be captured
(volume, login background, welcome suppression, avatar + name) as **First-Login
State**. Add the missing packages (Orca, VLC, a coordinate-capable weather
widget from the official repos). Autodetect the timezone at install with an
`Europe/Bucharest` fallback and drop the `UTC` pin on the reference box. Give VM
installs a Full-HD floor without seeding any monitor mode. The result: whatever
is on the `arch-combined` box today is what a first login looks like.

## User Stories

1. As the operator, I want a fresh KDE login to open straight to the desktop, so
   that I never see the Plasma Welcome Center.
2. As the operator, I want the Welcome Center kept suppressed across Plasma
   upgrades, so that a newer `plasma-welcome` version does not re-trigger it.
3. As the operator, I want the timezone detected automatically during install,
   so that the clock is correct without my intervention.
4. As the operator, I want the timezone to fall back to `Europe/Bucharest` when
   detection cannot run, so that an offline install still lands on my home zone.
5. As the operator, I want the `arch-combined` Host Profile to stop pinning
   `UTC`, so that the reference box reflects the real fleet behaviour.
6. As the operator, I want sound line in and line out at 100% on first login, so
   that audio is usable immediately.
7. As the operator, I want night light to follow sunrise and sunset, so that the
   screen warms on schedule without me configuring it.
8. As the operator, I want night light to work with no geoclue and inside a VM,
   so that it shifts reliably regardless of location services.
9. As the operator installing into a VM, I want at least Full-HD resolution, so
   that the desktop is usable without manually resizing the display.
10. As the operator, I want the VM Full-HD floor to leave real hardware
    untouched, so that no monitor is black-screened by a hardcoded mode.
11. As the operator, I want Orca installed, so that the screen reader works from
    first login.
12. As the operator, I want KDE printer support present and the print daemon
    enabled, so that I can add and use a printer out of the box.
13. As the operator, I want VLC to be the default video player, so that videos
    open in VLC.
14. As the operator, I want VLC installed while the shipped player stays present,
    so that I keep a fallback but VLC is the default.
15. As the operator, I want my Activities (Default + Dev) seeded, so that both
    activities exist on first login.
16. As the operator, I want my saved power-management profile seeded, so that
    power behaviour matches the reference box.
17. As the operator, I want the login screen and lock screen to both show the
    Horos wallpaper, so that they look consistent.
18. As the operator, I want each panel widget's individual settings seeded, so
    that widgets come up configured, not default.
19. As the operator, I want the Activity Pager to actually appear in the panel,
    so that it is not missing as it was after the last install.
20. As the operator, I want a weather widget that can target Râmnicu Vâlcea, so
    that the panel shows my city's weather.
21. As the operator, I want the weather widget to come from the official repos,
    so that there is nothing vendored or version-pinned to maintain.
22. As the operator, I want the weather widget in the same panel position as the
    stock one it replaces, so that my layout is unchanged.
23. As the operator, I accept Sibiu only if no widget can resolve Râmnicu Vâlcea,
    so that I always have a working forecast. (Resolved: the packaged widget
    targets Râmnicu Vâlcea by coordinate, so Sibiu is not needed.)
24. As the operator, I want my chosen avatar seeded, so that my user shows the
    lightbulb image.
25. As the operator, I want my display name ("Alex") seeded for the primary
    user, so that the greeter and session show my name.
26. As the operator, I want my Application Launcher favorites seeded, so that my
    pinned programs are present on first login.
27. As the operator, I want my window rules seeded, so that per-window behaviour
    matches the reference box.
28. As the operator, I want default applications (beyond video) seeded, so that
    file associations match the reference box.
29. As a stock/pure-KDE user, I want none of this opinionated look applied, so
    that pure KDE stays upstream Breeze (ADR 0112).
30. As a maintainer, I want the extended capture recorded as a point-in-time
    snapshot, so that I know re-tweaking Plasma means re-capturing.
31. As a maintainer, I want the First-Login State reconstructed (not copied) and
    documented as such, so that I do not expect it in the captured skel set.

## Implementation Decisions

### Captured Plasma Settings — extend the set (ADR 0111 / 0120)
- Re-snapshot the live `arch-combined` `~/.config` and overwrite the existing
  vendored skel files verbatim (konsave-style whole-file copy — no merging).
- **Add** to the captured set: `kactivitymanagerdrc` (+ `kactivitymanagerd-
  statsrc`), `powerdevilrc`, `mimeapps.list`, `plasma-welcomerc`, `kwinrulesrc`.
  The KDE adapter already loops over `skel/.config/*`, so new files seed with no
  adapter logic change.
- `powermanagementprofilesrc` stays a Plasma-6 migration stub; `powerdevilrc` is
  the real power config.
- The captured `plasma-org.kde.plasma.desktop-appletsrc` carries per-widget
  settings, favorites, launchers, and the Activity Pager — re-capture is what
  fixes the "pager missing" and "widget settings lost" reports.
- Continue to **exclude** the EDID-keyed monitor files (`kscreenrc`,
  `kwinoutputconfig.json`) — resolution stays autodetected (ADR 0110 / 0119).

### Night light (ADR 0120 / 0121)
- In the captured `kwinrc`, set `[NightColor] NightColorMode=Location` with fixed
  coordinates for Râmnicu Vâlcea (≈ 45.10 N, 24.37 E). Sunrise/sunset are then
  computed offline and inside the VM with no geoclue dependency. Automatic mode
  is rejected: geoclue is not installed, its network-location backend is defunct
  (MLS shutdown), and a VM has no WiFi/GPS fix.

### Weather widget — packaged, not vendored (ADR 0120)
- Add `plasma-applets-weather-widget-3` (official `extra` — blackadderkate's
  weather-widget-2, Kotelnik lineage) to the KDE package selection. Chosen over
  the richer `pnedyalkov91/advanced-weather-widget` precisely because the latter
  is not in AUR or the repos and would need vendoring + a version pin.
- Configure it in the captured `appletsrc` in the **same panel slot** the stock
  `org.kde.plasma.weather` occupied: provider **met.no** (keyless), location by
  **manual latitude/longitude/altitude** for Râmnicu Vâlcea.

### Packages (ADR 0120)
- Add `orca` (accessibility) and `vlc` (multimedia) to the KDE application
  selection. `haruna` stays installed; VLC is the captured default for video via
  `mimeapps.list`.
- KDE printer support (`print-manager`) is **already** in the selection and the
  Printing Service already enables `cups` by default on every host — so printing
  needs no new work beyond confirming it. No `system-config-printer` / `cups-pdf`
  unless later requested.

### First-Login State — reconstructed, not captured (ADR 0121)
- **Audio 100%**: an idempotent first-login autostart runs `wpctl set-volume` on
  `@DEFAULT_AUDIO_SINK@` and `@DEFAULT_AUDIO_SOURCE@` to `1.0`. Chosen over
  vendoring device-keyed WirePlumber/ALSA state.
- **Login background**: set the SDDM Breeze theme `Background` to the Horos
  wallpaper, in the KDE adapter's own SDDM drop-in (merges with the Display
  Manager Adapter's file, ADR 0069). Lock screen already carries Horos via the
  captured `kscreenlockerrc`.
- **Welcome suppression**: keep the `Hidden=true` `plasma-welcome.desktop`
  autostart **and** write `plasma-welcomerc [General] LastSeenVersion` to the
  installed `plasma-welcome` version (`pacman -Q`) at install time (robust across
  upgrades in a way a static captured version is not).
- **Avatar + display name**: seed the vendored 256×256 lightbulb PNG to
  `/etc/skel/.face` and write the Primary User's AccountsService record + icon at
  user creation; set the GECOS full name (default `"Alex"`) via `useradd -c`.
  Per-user by nature, so applied to the Primary User only.

### User creation
- Add an optional full-name accessor (default `"Alex"`) and pass it to
  `useradd -c` for the Primary User. No richer per-user `{name, fullname}` schema
  and no guided-menu surface — the minimal change that seeds the name.

### Timezone resolver (ADR 0118)
- New pure resolver `lib/config/timezone.sh`, modelled on the Printing Service
  resolver (`printing.sh`): JSON/inputs in, resolved zone out, no TTY.
- Resolve order: an explicit configured/guided value wins; otherwise geo-IP
  autodetect (`https://ipapi.co/timezone`, bounded curl mirroring the existing
  `--connect-timeout 2 --max-time 8` idiom); validate the result against
  `/usr/share/zoneinfo`; on any failure fall back to `Europe/Bucharest`.
- The network fetch is behind an **injectable seam** (env-override command /
  file, like guided-controller's `GUIDED_*_FILE`) so it is testable offline.
- Drop the `system.timezone: "UTC"` pin from the `arch-combined` Host Profile so
  the reference box reflects the resolver's behaviour.

### VM Full-HD floor (ADR 0119)
- Compose `video=Virtual-1:1920x1080` into the installed system's kernel cmdline
  when **install-time virtualization is detected** (`systemd-detect-virt` inside
  the chroot). The seam is the shared kernel-cmdline composition in
  `bootloader-common.sh`. Bare-metal installs get nothing, so ADR 0110's
  black-screen risk never applies; no `kscreen`/output file is seeded. "At least"
  is a floor — SPICE still scales up via preferred-mode autodetection.

## Testing Decisions

Good tests here assert **external behaviour at the highest existing seam** — what
files/keys land in the seed root, what packages the resolver emits, what the
`useradd`/cmdline invocation contains — never internal helper wiring. Network and
virtualization detection are exercised through **injected seams**, never live.

1. **KDE adapter** — `tests/extras/kde-adapter.bats` (existing seam: run `kde.sh`
   as a subprocess with `KDE_JSON` / `KDE_SEED_ROOT` / `KDE_SKEL_SRC` set and
   `pacman`/`systemctl` stubbed on `PATH`). Add cases: the new captured files land
   in `etc/skel/.config`; `kwinrc` carries `NightColorMode=Location` + coords;
   `appletsrc` carries the met.no weather config in the expected slot; the volume
   autostart `.desktop` is written; the SDDM drop-in sets the Horos `Background`;
   `plasma-welcomerc LastSeenVersion` is written from the stubbed `pacman -Q`; the
   avatar lands at `etc/skel/.face`; **stock/pure KDE seeds none of it** (ADR
   0112). Prior art: the existing skel/first-run/SDDM cases in the same file.
2. **Timezone resolver** — new `tests/config/timezone.bats` for
   `lib/config/timezone.sh`, structured like `tests/config/printing.bats`.
   Cases: explicit value wins; injected fetch returns a valid zone → used;
   injected fetch returns an invalid/empty zone → `Europe/Bucharest`; fetch
   fails (offline) → `Europe/Bucharest`. No live network.
3. **Package Resolver** — `tests/packages/resolver.bats` (existing). Assert the
   resolved KDE set contains `orca`, `vlc`, `plasma-applets-weather-widget-3`
   (content), complementing the adapter's mechanism-only sentinel test.
4. **User creation** — `tests/chroot/chroot-create-user.bats` (existing). Assert
   the `useradd`/`usermod` invocation carries `-c "Alex"` for the Primary User and
   that an explicit full name overrides the default.
5. **Bootloader cmdline** — `tests/boot/loader-entries.bats` (existing). With
   virt-detect stubbed present, the composed cmdline contains
   `video=Virtual-1:1920x1080`; stubbed absent (bare metal), it does not.
6. **Profile data** — the `arch-combined` `UTC`-pin removal is a data change
   validated by existing `tests/config/profile-loader.bats` /
   `tests/config/personal-profiles.bats`; behaviour is covered by seam 2.

## Out of Scope

- Enabling geoclue / KWin Automatic night-light mode (rejected in ADR 0121).
- Vendoring the richer Advanced Weather Widget or any third-party plasmoid.
- Seeding monitor resolution/refresh in-guest via `kscreenrc` /
  `kwinoutputconfig.json`, or any bare-metal resolution seeding (ADR 0110).
- A general per-user `{name, fullname}` schema, a guided full-name editor, or
  seeding avatar/name for any account other than the Primary User.
- `system-config-printer`, `cups-pdf`, or any printer package beyond the already
  present `print-manager`.
- Changing the guided timezone picker behaviour (the picker still wins when
  edited; autodetect only fills the default).
- Applying the extended look to stock/pure KDE (ADR 0112).

## Further Notes

- The extended Captured Plasma Settings are a **point-in-time snapshot** of
  `arch-combined`; re-tweaking Plasma later means re-capturing, exactly as the
  vendored Noctalia cache (ADR 0109) and the original capture (ADR 0111).
- The First-Login State (volume, login background, welcome version, avatar/name)
  is the one part of the "looks like `arch-combined`" guarantee that is
  reconstructed at install/first-login rather than verbatim-copied.
- New glossary terms recorded in `CONTEXT.md`: **Captured Plasma Settings**,
  **First-Login State**.
- Widget coordinates: Râmnicu Vâlcea ≈ 45.10 N, 24.37 E, altitude ~240 m; look up
  a precise altitude at capture time.
- Reachability of the geo-IP endpoint from the Arch ISO is not verifiable from
  the dev environment; the `Europe/Bucharest` fallback covers a block.
