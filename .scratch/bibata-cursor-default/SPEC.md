# Spec: Bibata Modern Ice as the seeded default cursor

Status: done (commits c1242d3, e8065a1). Bibata seeded + AUR-declared on KDE,
niri, Hyprland; ~/.icons/default on all three; bats green.

Related: ADR 0098 (this feature — Bibata Modern Ice seeded across KDE, niri,
Hyprland). Extends ADR 0088 (KDE adapter seeds DE defaults incl. cursors) and
ADR 0041 (AUR packages install via the Primary-User paru pass); amends ADR
0088's Breeze-cursors default. Lands in the same adapters as the shared-shell
work (ADR 0097, `.scratch/noctalia-shared-shell/`) but is independent of it.

## Problem Statement

The operator wants one cursor — Bibata Modern Ice — shipped and active by default
on every desktop, so KDE, niri, and Hyprland look consistent out of the box.
Today KDE seeds Breeze cursors (ADR 0088) and niri/Hyprland seed no cursor at
all, so the pointer differs per desktop. Bibata is AUR-only, and the prebuilt
package ships Xcursor only — but Hyprland should use a real hyprcursor cursor,
not an Xcursor fallback.

## Solution

Seed Bibata Modern Ice as the active default cursor on all three DE adapters,
from a single AUR package that ships **both** the hyprcursor and Xcursor formats.
KDE and niri use the Xcursor theme; Hyprland uses the hyprcursor theme with the
Xcursor theme as its XWayland/legacy fallback. The pointer is identical across
the three desktops on a fresh install, at size 24.

## User Stories

1. As an operator, I want the same cursor on KDE, niri, and Hyprland, so that the
   pointer looks consistent no matter which desktop I log into.
2. As an operator on Hyprland, I want a real hyprcursor Bibata theme, so that I
   get crisp, correctly-scaled cursors from Hyprland's native cursor engine.
3. As an operator on Hyprland, I want XWayland and legacy apps to still show
   Bibata via the Xcursor fallback, so that the cursor does not revert for
   non-hyprcursor apps.
4. As an operator on niri, I want Bibata as the Xcursor theme, so that the
   scrollable desktop matches the others.
5. As an operator on KDE, I want Bibata to replace Breeze as the default cursor,
   so that KDE matches the wlroots desktops.
6. As an operator, I want GTK and XWayland apps to follow Bibata via the standard
   default-icon path, so that toolkits agree on the cursor.
7. As an operator, I want the cursor at size 24 everywhere, so that scale is
   consistent across desktops.
8. As an operator on a headless or minimal host, I want no cursor theme
   installed, so that a box with no desktop is not carrying a GUI cursor package.
9. As an operator, I want the cursor to be active on first login with no manual
   selection, so that the default is truly the default.
10. As a maintainer, I want one cursor package serving all three desktops, so
    that there is no per-desktop package divergence or file conflict to manage.
11. As a maintainer, I want the cursor declared where the DE is selected, so that
    it installs only alongside a desktop, via the existing AUR pass.

## Implementation Decisions

- **One package, both formats: `bibata-cursor-git`.** It builds the hyprcursor
  *and* the Xcursor Bibata theme into the same `Bibata-Modern-Ice` theme
  directory, so a single package serves KDE/niri (Xcursor) and Hyprland
  (hyprcursor). It conflicts with the prebuilt `bibata-cursor-theme-bin` (both
  own that theme dir), so it must be the sole Bibata everywhere — which one
  shared package makes trivial. The prebuilt Xcursor-only variant is rejected
  because it cannot provide hyprcursor.
- **Declared per-adapter, not fleet-wide.** Added to each DE adapter's `aur`
  list (KDE, niri, Hyprland) and unioned into the Profiles Runner's single paru
  invocation, so it lands only where a desktop is selected and never on a
  headless/minimal host. A fleet-wide `hosts/core` entry is rejected for that
  reason.
- **Applied as the active default per surface, size 24:**
  - **KDE** — the cursor theme in `kcminputrc` is set to `Bibata-Modern-Ice`
    (replacing `breeze_cursors`) alongside the existing `~/.icons/default`
    default-icon seed. The rest of the Breeze Dark look is unchanged.
  - **niri** — the compositor's native cursor config node sets the Xcursor theme
    to `Bibata-Modern-Ice` at size 24.
  - **Hyprland** — `HYPRCURSOR_THEME`/`HYPRCURSOR_SIZE` env set to
    `Bibata-Modern-Ice`/24 (primary), with `XCURSOR_THEME` kept as the
    XWayland/legacy fallback.
  - `~/.icons/default` is seeded on all three so GTK / XWayland apps resolve the
    same theme.
- **Build cost accepted.** `bibata-cursor-git` is a source/VCS build (Python,
  librsvg, xorg-xcursorgen pulled in the paru pass) — slower than a prebuilt,
  accepted because it is the only package delivering both formats.

## Testing Decisions

- **What a good test asserts:** externally observable adapter behaviour — that
  each adapter declares `bibata-cursor-git` in its AUR set and writes the cursor
  default into the expected seeded config surface — never internal helpers. Prior
  art: `kde-adapter.bats` (already asserts KDE's seeded Breeze look, incl.
  `kcminputrc` and `~/.icons/default`), and the `niri-adapter.bats` /
  `hyprland-adapter.bats` skel-seed assertions.
- **`kde-adapter.bats`.** The seeded `kcminputrc` cursor theme is
  `Bibata-Modern-Ice` (not `breeze_cursors`) and `~/.icons/default` inherits it.
- **`niri-adapter.bats`.** The seeded niri config carries the Bibata cursor node
  at size 24; `~/.icons/default` is seeded.
- **`hyprland-adapter.bats`.** The seeded `hyprland.conf` sets the hyprcursor env
  to Bibata at size 24 and retains an Xcursor fallback; `~/.icons/default` is
  seeded.
- **`profiles/profiles-aur.bats`.** `bibata-cursor-git` is unioned into the paru
  pass when a DE adapter that declares it is selected, and absent for a
  desktop-less host.
- **Not covered by bats:** that the cursor actually renders as Bibata at runtime
  — that is a live-session check (VM/desktop), out of scope for the unit seams.

## Out of Scope

- The shared Noctalia shell work (ADR 0097) — a separate feature in the same
  adapters.
- Cursor themes other than Bibata Modern Ice, or a per-host/menu cursor selector
  — a single seeded default is the whole ask.
- hyprcursor for KDE or niri — those use Xcursor; hyprcursor is Hyprland-only.
- Changing the seeded cursor *size* per desktop — 24 everywhere.

## Further Notes

- Confirm at implementation time that setting `HYPRCURSOR_THEME` alone applies the
  cursor on a fresh Hyprland login with no `hyprctl setcursor` nudge; if a nudge
  is needed, prefer an `exec-once` over a manual step.
- The `bibata-cursor-theme-bin` ↔ `bibata-cursor-git` file conflict means an
  operator with the prebuilt already installed must remove it first; a fresh
  install has neither, so the ordering is only a concern on upgrade of an
  existing box.
