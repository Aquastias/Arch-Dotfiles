# Spec: A ready-to-use KDE loadout on first login

Status: ready-for-agent

Relates to: ADR 0087 (`apps_extra` section), ADR 0088 (adapter seeds DE
config defaults). Extends ADR 0021 (adapter owns DE packages).

## Problem Statement

When the operator selects KDE and boots the freshly installed machine,
the desktop is bare and raw: a small default app set, light theme, and
every app greeting them as if launched for the first time (welcome
screens, tips, first-run prompts). Getting to "my usual, fully-loaded,
dark KDE that behaves like I've used it before" is a long manual chore
repeated on every install. The operator wants the installer to hand them
a KDE that is already theirs.

## Solution

The KDE Desktop Environment Adapter ships a curated, fully-loaded KDE:
the operator's chosen application set, the optional plugins/backends that
make those apps capability-complete, a Breeze Dark look (Papirus-Dark
icons, Breeze cursors) applied by default, a matching dark SDDM login,
and first-run noise suppressed so apps open ready. Editor language
servers for the operator's languages land on their real machines. On
first login, KDE is already configured — nothing looks first-run.

## User Stories

1. As the operator, I want my full curated KDE app set installed by
   default when I select KDE, so that I do not hand-install ~45 apps
   after every install.
2. As the operator, I want file management (dolphin, ark, filelight,
   krename, krusader) ready, so that I can manage files immediately.
3. As the operator, I want documents/office (okular, calligra,
   ghostwriter) ready, so that I can read and write documents.
4. As the operator, I want graphics/creative tools (gwenview, krita,
   digikam, kolourpaint, kcolorchooser, karbon-via-calligra) ready.
5. As the operator, I want multimedia (kdenlive, elisa, k3b, haruna)
   ready, so that I can edit video, play music, burn discs, and watch
   video.
6. As the operator, I want a video player (haruna), so that my media
   setup is not audio-only (Elisa).
7. As the operator, I want a calendar/PIM app (merkuro), so that my
   loadout is not missing scheduling.
8. As the operator, I want scanning (skanpage) ready, so that I can scan
   multi-page documents.
9. As the operator, I want security/crypto tools (kleopatra,
   kwalletmanager) ready, so that I can manage keys and secrets.
10. As the operator, I want system/utility tools (konsole, yakuake,
    partitionmanager, kfind, isoimagewriter, sweeper, kcalc, okteta,
    kmag, kiten, kommit) ready.
11. As the operator, I want remote-desktop tools (krdc, krfb) ready, so
    that I can connect to and share desktops.
12. As the operator, I want networking (kdeconnect, ktorrent) ready, so
    that my phone integrates and I can torrent.
13. As the operator, I want a 2FA client (keysmith) ready, so that I can
    generate OTP codes.
14. As the operator, I want redundant/dead entries pruned (karbon,
    kclock, skanlite, arianna, kgpg, kompare), so that my set has no
    duplicates or mobile-only apps that do nothing on desktop.
15. As the operator, I want kdiff3 instead of kompare, so that I get a
    diff-and-merge tool rather than a dated diff-only one.
16. As the operator, I want my KDE apps' optional plugins/backends
    installed, so that the apps are capability-complete out of the box.
17. As the operator, I want Dolphin plugins (VCS integration,
    admin://, PDF/video/image thumbnails, MOBI, CLI tools), so that
    Dolphin is fully featured.
18. As the operator, I want Ark to open every archive (7zip, unrar), so
    that extraction never fails on format.
19. As the operator, I want Okular to open EPUB/MOBI/CBR, so that it
    reads all my document formats.
20. As the operator, I want Gwenview/Krita to open extended image
    formats (kimageformats, qt6-imageformats), so that PSD/WEBP/TIFF
    just work.
21. As the operator, I want Krita's G'MIC filters, so that I have the
    full painting toolkit.
22. As the operator, I want Kdenlive's motion tracking, voice
    noise-suppression, and screen capture (opencv,
    noise-suppression-for-voice, recordmydesktop), so that editing is
    complete.
23. As the operator, I want digiKam RAW import via darktable, so that I
    can process camera RAW files.
24. As the operator, I want KDE Connect to browse my phone filesystem
    (sshfs), so that file transfer works.
25. As the operator, I want the desktop to be Breeze Dark by default,
    so that I do not switch from the light default every install.
26. As the operator, I want Papirus-Dark icons kept in KDE, so that the
    icon set matches my preference.
27. As the operator, I want Breeze cursors, so that the cursor matches
    the Breeze Dark look after Catppuccin is removed.
28. As the operator, I want GTK apps to follow the dark look
    (breeze-gtk, kde-gtk-config), so that GTK apps are not light amid a
    dark desktop.
29. As the operator, I want the Catppuccin GTK theming removed from my
    stow payload, so that the desktop is coherently Breeze Dark
    (Catppuccin re-addable later).
30. As the operator, I want the SDDM login screen in Breeze dark, so
    that login-to-session is visually seamless.
31. As the operator, I want KDE apps to not behave first-run, so that a
    fresh login feels like a machine I already use.
32. As the operator, I want global welcome noise off (Plasma Welcome
    Center, tip-of-the-day, what's-new popups), so that nothing nags me
    on first login.
33. As the operator, I want per-app first-run state seeded for the apps
    I open most (Dolphin, Konsole, Kate, Okular, Spectacle, Gwenview,
    Ark), so that they open configured.
34. As the operator, I want desktop search working (Baloo on), so that I
    can find files immediately.
35. As the operator, I want the same defaults applied to any user
    created on the machine, so that the ready experience is not tied to
    one account.
36. As the operator, I want editor language servers for my languages
    (bash, yaml, js/ts, json/css/html, rust, go, zig, c/c++), so that
    Kate has code intelligence out of the box.
37. As the operator, I want language servers on my real machines
    (desktop and laptop), not on VMs, so that dev tooling is where I
    develop and VM fixtures stay lean.
38. As the operator, I want AUR-only servers accepted where no repo
    package exists (vscode-langservers-extracted), so that json/css/html
    intelligence still works.
39. As the operator, I want the Nix server skipped for now, so that a
    flaky AUR build does not risk every install.
40. As the operator, I want every added app/plugin still deselectable
    in the Guided Installer, so that a given machine can trim the set.
41. As the operator, I want `explain-packages` and the Guided `derived`
    view to reflect the new sections accurately, so that I can audit
    what a KDE install actually pulls.
42. As the operator, I want the adapter's repo-only guarantee kept
    (no new AUR in the adapter), so that selecting KDE never triggers an
    AUR build.
43. As a maintainer, I want the KDE app set split by provenance
    (`apps_list` = group members, `apps_extra` = non-group KDE apps),
    so that `apps_list`'s mechanical membership rule stays verifiable.
44. As a maintainer, I want plugin/backend packages in one adapter
    `plugins` section keyed by app, so that they toggle alongside the
    apps they enhance.

## Implementation Decisions

Modules built or modified:

- **KDE adapter config (`extras/desktop/kde/install-kde.jsonc`)** gains
  two new sibling Categorized-List sections beside `apps_list`:
  - `apps_extra` — KDE-ecosystem repo packages whose pacman `Groups`
    does NOT contain `kde-applications` (per ADR 0087). Holds `krita`,
    `digikam`, `okteta`, `kommit`, `krename`, `krusader`, `kdiff3`.
  - `plugins` — optional-dependency enhancers keyed by app (per ADR
    0088). Same 2-level `{ category: { pkg: bool } }` shape, parsed in
    bool mode by the Categorized List Parser, installed in the same
    pacman pass, deselectable in the Guided Installer.
  - `apps_list` is re-curated to the operator's group-member roster
    plus the three plasma-group no-ops (`spectacle`,
    `plasma-systemmonitor`, `discover`) that `plasma-meta` already
    pulls (listed to document intent; `--needed` makes them free).
- **KDE adapter script (`extras/desktop/kde/kde.sh`)**:
  - Parses and installs `apps_extra` and `plugins` in addition to
    `apps_list`.
  - Adds `breeze-gtk` and `kde-gtk-config` to the shell phase (so GTK
    follows the dark look); `papirus-icon-theme` is already installed.
  - Seeds DE config defaults (theme + first-run) into a **seed root**
    (default `/`), writing to `/etc/skel/.config/*` for user-owned,
    later-editable state and `/etc/xdg/*` for read-only fallbacks (per
    ADR 0088). The seed root is an injectable variable for testing.
  - Writes the SDDM Breeze-dark configuration.
- **Package Resolver (`lib/packages/resolver.sh`)** learns the two new
  sections, emitting new sources `kde-apps-extra` and `kde-plugins`
  (layer `derived`, category `Environment`), so `explain-packages` and
  the Guided `derived` view stay accurate.
- **Host Core (`hosts/core/profile.jsonc`)** gains the Kate language
  servers: `packages.repo` += `bash-language-server`,
  `yaml-language-server`, `typescript-language-server`, `rust-analyzer`,
  `gopls`, `zls`, `clang`; `packages.aur` += `vscode-langservers-
  extracted`. VM fixtures already opt out via `packages.inherit:
  false`, so servers land on desktop/laptop only.
- **Stow payload (`.config/gtk-3.0`, `.config/gtk-4.0`)**: the
  Catppuccin GTK theming is removed; `settings.ini` is rewritten to the
  Breeze / Papirus-Dark / Breeze-cursors defaults.

Theme content seeded (behavioral, not byte-locked): `kdeglobals` with
the Breeze Dark color scheme / look-and-feel
(`org.kde.breezedark.desktop`) and `Icons=Papirus-Dark`; the Breeze
cursor theme; look-and-feel supporting files as needed.

First-run content seeded: global welcome/tips/what's-new disabled; a
default Konsole profile pre-created; per-app first-run flags cleared for
Dolphin, Konsole, Kate, Okular, Spectacle, Gwenview, Ark; Baloo left
enabled.

Routing rule for the two additions (`haruna`, `merkuro`): placed by
their **actual** pacman `Groups` at build time — group member →
`apps_list`, otherwise → `apps_extra`. No group membership pre-assumed.

Provenance / AUR contract: everything in the adapter resolves to the
`extra` repo; the adapter `aur` block stays exactly `qt6ct-kde`. The
only new AUR package is `vscode-langservers-extracted`, and it lives in
Host Core, never the adapter — the adapter's repo-only guarantee holds.

## Testing Decisions

Good tests here assert **external behavior** — which packages the
adapter emits and which files it seeds — never the exact byte content of
a config file or an internal function name. Two existing seams, both
extended (no new harness):

- **Seam 1 — KDE adapter subprocess** (`tests/extras/kde-adapter.bats`,
  running `kde.sh` with `pacman`/`systemctl` stubbed and `KDE_JSON`
  injected). New coverage:
  - `apps_extra` and `plugins` selected leaves are installed;
    deselected (`false`) leaves are not; malformed shapes abort with a
    pathed parser error (mirrors the existing `apps_list` cases).
  - With the seed-root variable pointed at a temp dir, the theme files
    land under `/etc/skel` and `/etc/xdg` and carry the load-bearing
    keys (Breeze Dark color scheme, `Papirus-Dark` icons, Breeze
    cursors); the first-run suppression files land. Assert presence and
    key values, not full file bytes.
  - The shipped-`install-kde.jsonc` regression lock is rewritten to the
    new `apps_list` roster, with sibling locks asserting `apps_extra`
    and `plugins` membership and that the pruned entries (`karbon`,
    `kclock`, `skanlite`, `arianna`, `kgpg`, `kompare`) appear nowhere.
- **Seam 2 — Package Resolver** (`tests/packages/resolver.bats`,
  `tests/explain-packages.bats`). New coverage: a KDE-selected effective
  config reports `kde-apps-extra` and `kde-plugins` sources; the Host
  Core language servers surface with the correct repo/aur layer.

Prior art: the existing `apps_list` selected/deselected/malformed cases
and the "shipped apps_list is exactly N entries" lock in
`kde-adapter.bats`; the derived-source assertions in `resolver.bats` and
`explain-packages.bats`.

## Out of Scope

- Deep, exhaustive per-app first-run tuning across all ~45 apps — only
  the curated heavy-hitters get per-app first-run state (ADR Q4-B).
- The Nix language server (`nil`/`nixd`) — skipped until an AUR build
  stabilizes; addable later with no structural change.
- A first-boot service to apply themes at runtime
  (`plasma-apply-lookandfeel`) — rejected in ADR 0088; seeding is
  chroot-time file placement only.
- Re-theming KDE to Catppuccin for cross-toolkit coherence — the
  operator chose Breeze Dark verbatim; Catppuccin is only removed from
  GTK, re-addable later.
- Any change to the Display Manager Adapter's ownership (ADR 0069) —
  only the SDDM theme is set, not package/enable ownership.

## Further Notes

- Two pre-existing `apps_list` entries not in the operator's authoritative
  roster are dropped as part of adopting it: `kompare` (replaced by
  `kdiff3`) and `keditbookmarks` (not requested). Both are trivially
  re-addable on request.
- The pre-existing `apps_list` already violated ADR 0021's R21 rule by
  holding non-group apps (`krita`, `krename`, `krusader`, `kdiff3`);
  this work relocates them to `apps_extra`, fixing the violation.
- `spectacle`, `plasma-systemmonitor`, and `discover` are `plasma`-group
  components already pulled by `plasma-meta`; listing them is a
  documented `--needed` no-op, not an R21 exception.
- The `/etc/skel` seed is copied into each home at user creation, which
  the Runner performs AFTER the chroot extras phase — so skel is
  populated before any user exists, with no ordering hazard (ADR 0088).
- Language-server packages pull their language toolchains as hard deps
  (nodejs, go, rust-src, zig, llvm); this footprint is intended per the
  operator's language list.
