# PRD: Umbriel compositor + Default Session

Status: ready-for-agent

Grounding: [ADR 0159](../../docs/adr/0159-umbriel-adapter-and-default-session.md)
(design), upstream docs.noctalia.dev/umbriel (no Arch Wiki page exists).

## Problem Statement

The operator wants Umbriel, the Noctalia project's own wlroots compositor, on
their desktop and laptop, and wants it to be what a fresh login lands on.
Today the installer knows only KDE, niri and Hyprland. There is no notion of
a default desktop either: on a host with several desktops, the display
manager just picks whatever it finds first or remembers. The Feature Audit
cannot prove Umbriel works, because nothing installs or probes it.

## Solution

A fourth Desktop Environment Adapter, Umbriel, joins niri and Hyprland as a
wlroots compositor under the shared Wayland Shell Companion (Noctalia). It
ships a curated, stowable Umbriel config that uses the operator's shared bind
map. A new **Default Session** concept makes `environment.desktop[0]` the
desktop a fresh login lands on. Every Display Manager Adapter seeds it as the
remembered last session, so it is a first-boot preselect, never a lock. The
`desktop` and `laptop` Host Profiles list Umbriel first. An `umbriel-pure`
Stock Profile and full Feature Audit coverage complete the set.

## User Stories

1. As the operator, I want Umbriel installable as a desktop, so that I can
   use the Noctalia project's own compositor.
2. As the operator, I want `umbriel` accepted in `environment.desktop`, so
   that a Host Profile can select it like `niri` or `hyprland`.
3. As the operator, I want an unknown desktop value still rejected at load,
   so that adding Umbriel does not weaken the closed schema.
4. As the operator, I want Umbriel's packages to come from AUR through the
   vetted paru pass, so that the only real packages (`umbriel-git`,
   `xdg-desktop-portal-umbriel-git`) pass the same trust gate as other AUR
   packages.
5. As the operator, I want the Umbriel portal installed with the compositor,
   so that screen sharing works in browsers and Discord.
6. As the operator, I want the Umbriel adapter to enable seatd and put users
   in the `seat` group, so that an Umbriel-only host gets DRM master on the
   AMD laptop without relying on Hyprland being present.
7. As the operator, I want Umbriel to appear exactly once in every display
   manager's session list, so that I am not offered duplicate entries.
8. As the operator, I want the Noctalia shell layered on Umbriel when
   `wayland_shell` is `noctalia`, so that Umbriel looks and behaves like my
   niri/Hyprland sessions.
9. As the operator, I want `wayland_shell: none` to give me bare Umbriel that
   seeds nothing, so that the behaviour matches niri and Hyprland.
10. As the operator, I want Noctalia's palette applied to Umbriel through the
    `umbriel` template it already ships, so that compositor borders/effects
    follow the theme.
11. As the operator, I want a curated Umbriel config seeded into new users'
    homes, so that first login is ready rather than first-run.
12. As the operator, I want the same curated config stowable from the repo,
    so that I can apply it on an existing machine.
13. As the operator, I want the curated config split into `conf.d/` parts
    (binds, look, input, autostart), so that it matches how niri/Hyprland
    configs are organised.
14. As the operator, I want Umbriel to autostart Noctalia in the curated
    config, so that the shell comes up with the session.
15. As the operator, I want Umbriel's binds to follow my shared
    niri/Hyprland bind map, so that muscle memory carries across compositors.
16. As the operator, I want Meta+X to close the focused window on Umbriel, so
    that close behaves the same in every session.
17. As the operator, I want Umbriel-only features (overview, tab groups,
    scratchpad) on keys the shared map leaves free, so that I can use what
    makes Umbriel different without breaking shared binds.
18. As the operator, I want the Bibata Modern Ice cursor on Umbriel, so that
    the cursor matches the other desktops.
19. As the operator, I want click-to-focus and the clipboard keep-alive on
    Umbriel, so that wlroots desktop behaviour is consistent.
20. As the operator, I want xdg user dirs generated on Umbriel sessions, so
    that the wlroots desktop completion is the same on all three
    compositors.
21. As the operator, I want monitor resolution left autodetected on Umbriel,
    so that no host-specific output config is vendored.
22. As the operator, I want the first element of `environment.desktop` to be
    the Default Session, so that the order I write is the order that matters.
23. As the operator, I want a fresh login on desktop/laptop to preselect
    Umbriel, so that it is my default without extra steps.
24. As the operator, I want my next session pick at the greeter to be
    remembered over the Default Session, so that the default never locks me
    in.
25. As the operator, I want the Default Session honoured by noctalia-greeter,
    greetd + tuigreet and SDDM alike, so that the concept does not depend on
    which display manager resolves.
26. As the operator, I want a host whose `desktop` is a single entry to keep
    working as today, so that the change is a no-op there.
27. As the operator, I want a host with no desktop to seed no Default
    Session, so that headless installs are untouched.
28. As the operator, I want the `desktop` and `laptop` profiles to become
    `umbriel, kde, niri, hyprland`, so that both machines default to Umbriel
    and keep the other desktops as fallbacks.
29. As the operator, I want desktop and laptop to keep installing the same
    package set, so that the one-image-two-machines rule holds.
30. As the operator, I want Umbriel selectable in the Guided Installer's
    desktop row, so that ad-hoc installs can pick it.
31. As the operator, I want the Guided desktop row to mark the first pick as
    default, so that the Default Session rule is visible while choosing.
32. As the operator, I want the Guided profile preview to show which desktop
    is the default, so that I can see it before seeding from a profile.
33. As the operator, I want the Guided `stock` Cycle Field to work with
    Umbriel, so that a stock Umbriel install is reachable without a profile.
34. As the operator, I want an `umbriel-pure` Stock Profile, so that I can
    install upstream-stock Umbriel like `niri-pure`.
35. As the operator, I want `umbriel-pure` to seed nothing and fall back to
    Umbriel's packaged config, so that it is truly stock.
36. As the operator, I want `umbriel-pure` installable as
    `install.sh --profile umbriel-pure`, so that it works like the other
    Stock Profiles.
37. As the operator, I want the Package Resolver to report Umbriel's packages
    from the same data the adapter installs, so that install and query
    cannot drift.
38. As the operator, I want a Feature Audit probe for Umbriel that runs in
    the live Umbriel session, so that a broken session is a Finding.
39. As the operator, I want the probe to run `umbriel config validate` on the
    shipped config, so that an upstream config-key change surfaces as a
    Finding, not a silent break.
40. As the operator, I want the probe to check that Umbriel's IPC answers, so
    that a hung compositor is caught.
41. As the operator, I want the shared wlroots checks (Noctalia running, Qt
    theming, xdg dirs, clipboard, portal) to run on Umbriel too, so that it
    is held to the same bar as niri/Hyprland.
42. As the operator, I want every shipped Umbriel bind to declare an audit
    expectation, so that an unproven bind is itself a Finding.
43. As the operator, I want Umbriel binds driven by real keyboard input in
    the audit, so that binds are proven end to end.
44. As the operator, I want Umbriel in the `arch-audit` max-feature host, so
    that the base Audit Run covers it.
45. As the operator, I want an `umbriel-pure` Audit Variant, so that the
    stock path is audited like `niri-pure` and `hyprland-pure`.
46. As the operator, I want curated-only Umbriel checks skipped (not failed)
    on `umbriel-pure` through the Probe Gate, so that stock variants are not
    judged by features they do not ship.
47. As the operator, I want the audit's desktop/laptop variants to land on
    Umbriel first, so that the Default Session is proven on real hosts.
48. As the operator, I want the Umbriel adapter documented in the glossary
    and ADR, so that a future reader knows why it is AUR-only and why
    `desktop[0]` matters.

## Implementation Decisions

- **Umbriel adapter**: a new Desktop Environment Adapter directory, core-only
  like niri. It adds no runner code changes, since dispatch is by
  convention. It installs no repo compositor package (none exists). It
  declares `umbriel-git` + `xdg-desktop-portal-umbriel-git` in its adapter
  `aur` list, alongside the fleet theming deps every DE adapter declares
  (`bibata-cursor-git`, `qt6ct-kde`). `wlroots0.20` and the other deps come
  from `extra` through the AUR package's dependencies.
- The upstream package ships `umbriel.desktop` (Name=Umbriel),
  `start-umbriel` and a systemd user `umbriel.service`. The adapter authors
  no session shim. It does need to make sure the session appears once in the
  curated session dir that sddm/tuigreet are pinned to.
- AUR packages install in the Profiles Runner's paru pass, after the chroot
  DE adapter. Seeding and session-file work that depends on the installed
  package must therefore not assume the binary exists at adapter time
  (follow how niri/Hyprland handle AUR-delivered parts).
- **seatd**: the Umbriel adapter installs and enables seatd and relies on the
  `seat` group (ADR 0068 pattern). This must be idempotent alongside the
  Hyprland adapter on multi-desktop hosts.
- **Wayland Shell Companion**: Umbriel becomes a third wlroots compositor in
  the shared Noctalia preset module. The per-compositor plugin slice is
  empty. Every place that tests "is a wlroots compositor"
  (niri/Hyprland lists in environment validation, the Probe Gate's shell
  check, live-keybinds' session-name mapping) gains `umbriel`.
- **Pure package map**: like niri's, a pure Umbriel package-map module is
  shared by the adapter and the Package Resolver, so they cannot drift.
- **Curated config**: single-source stow payload at the repo root
  (`config.toml` + `conf.d/` includes), seeded into `/etc/skel` by the
  adapter. Binds are translated from the shared niri/Hyprland bind map and
  replace upstream's defaults (Meta+X close, not Mod+Q). Umbriel-only
  actions (overview, tab groups, scratchpad) go on keys the shared map does
  not use. Noctalia's existing `umbriel` theme template is the colour
  source. Cursor is Bibata Modern Ice. Autostart is `noctalia`. Output
  config stays absent (autodetected).
- **Schema**: `umbriel` is added to the closed `environment.desktop` enum and
  to the Guided Installer's desktop options. No new profile key.
- **Default Session**: defined as `environment.desktop[0]`. Each Display
  Manager Adapter seeds it as the remembered last session:
  - noctalia-greeter: `[session].last` in its state, not `[session].default`.
  - greetd + tuigreet: tuigreet's `--remember-session` cache. Verify its
    current on-disk format against upstream before writing.
  - SDDM: `state.conf` `[Last] Session=`.
  - Skipped when the desktop set is empty. It's an exact equivalent of today
    for single-desktop hosts.
  The value written is the session's desktop-entry identity each DM matches
  on. Impermanence: these state paths must survive rollback (noctalia-greeter
  state already does, per ADR 0158; check the others).
- **Host Profiles**: `desktop` and `laptop` `environment.desktop` become
  `["umbriel","kde","niri","hyprland"]`. Package sets stay identical between
  the two.
- **`umbriel-pure`**: a new Stock Profile modelled on `niri-pure`: one
  desktop, `stock: true`, bare compositor, seeds nothing.
- **Guided**: the desktop row and profile-preview tree mark the first entry
  as `(default)`. The existing multi-select order decides it.
- **Feature Audit**: a co-located Umbriel probe gated on the running session.
  It runs `umbriel config validate`, an IPC query (`umbriel workspaces
  --json`) and the shared wlroots checks. Umbriel also gets a co-located
  bind-expectation file covering every shipped bind, a bind parser if the
  generic one can't read TOML binds, Umbriel in `arch-audit`, and an
  `umbriel-pure` entry in the Audit Manifest.
- Documentation: ADR 0159 (written) and the glossary (Default Session term,
  four adapters, written). Update the installer README/REFERENCE desktop
  lists.

## Testing Decisions

- Good tests assert external behaviour: what a profile resolves to, which
  files an adapter seeds and with what content, what a DM records as last
  session, what a live session answers. They do not assert internal function
  calls.
- **Top seam, Feature Audit VM run**: an Audit Run over `arch-audit`,
  `umbriel-pure`, `desktop` and `laptop`. It proves a real Umbriel session
  starts, Noctalia runs, the config validates, IPC answers, every bind fires,
  and desktop/laptop land on Umbriel at first login. Verified in the VM per
  the one-VM-at-a-time rule.
- **Offline seams (existing only, no new seams)**:
  1. Fleet Golden snapshot: a deliberate regeneration of the `desktop` and
     `laptop` golden fixtures for the new desktop order + Umbriel packages,
     with the same-package-set check still passing.
  2. Adapter bats through the existing injectable seed-root seam, as in the
     niri/Hyprland adapter and DM adapter tests. Covers the Umbriel adapter's
     seeds and seatd, plus each DM adapter's Default Session seed (multi,
     single, empty desktop set).
  3. Guided replay / profile-equivalence: the `desktop[0]` default marker,
     and Guided ≡ `--profile` for `umbriel-pure` and desktop.
- Also touched: environment validation/resolution bats (enum, wlroots
  predicate), the Package Resolver derived-set bats, the pure-profiles bats,
  and the feature-audit manifest coverage bats.

## Out of Scope

- Removing niri or Hyprland from any host.
- Switching to non-git `umbriel` packages (only once upstream tags a release).
- A forced (non-remembered) default session, or a separate
  `default_session` profile key.
- Umbriel-specific Noctalia plugins (none exist).
- Packaging Umbriel into a custom repo, or building it in the live-CD phase
  outside the AUR pass.
- Changing the `auto` display-manager rule (ADR 0158 stays).

## Further Notes

- Upstream is young: config keys and binds may change between `-git`
  builds. The audit's `umbriel config validate` probe is the tripwire.
- Umbriel needs systemd ≥ 254 for managed sessions. Arch satisfies this.
- `wlroots0.20` is a strict `>=0.20.1 <0.21` pin upstream, so a wlroots bump
  in `extra` can break the build until upstream follows.
