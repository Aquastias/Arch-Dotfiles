# Bibata Modern Ice is the seeded default cursor across KDE, niri, Hyprland

---
Status: accepted. Extends ADR 0088 (KDE adapter seeds DE defaults, incl.
cursors) and ADR 0041 (AUR packages install via the Primary-User paru pass).
Amends ADR 0088's Breeze-cursors default.
---

The operator wants one cursor — **Bibata Modern Ice** — shipped and active by
default on every desktop, so KDE, niri, and Hyprland look consistent out of the
box. Bibata is **AUR-only**. The prebuilt `bibata-cursor-theme-bin` ships
**Xcursor only** (no hyprcursor), and the Hyprland requirement is a real
hyprcursor cursor, not an Xcursor fallback.

## Decision

Seed **Bibata Modern Ice** as the active default cursor on all three DE
adapters, via a **single package: `bibata-cursor-git`** (AUR).

- **One package, both formats.** `bibata-cursor-git` builds both the hyprcursor
  *and* the Xcursor theme into `/usr/share/icons/Bibata-Modern-Ice/`, so the same
  package serves KDE/niri (Xcursor) and Hyprland (hyprcursor). It **conflicts**
  with `bibata-cursor-theme-bin` (both own that dir), so it must be the sole
  Bibata everywhere — which the shared package makes trivial. Build deps
  (`python≥3.12`, `librsvg`, `xorg-xcursorgen`) are pulled in the paru pass.
- **Declared per-adapter (ADR 0041 path).** Added to each DE adapter's `aur`
  list (KDE, niri, Hyprland), unioned into the Profiles Runner's paru invocation
  — so it lands only where a desktop is selected, never on a headless/minimal
  box.
- **Applied as the active default per surface**, size 24 everywhere:
  - **KDE** — `kcminputrc` `cursorTheme=Bibata-Modern-Ice` (replacing
    `breeze_cursors`) + `~/.icons/default` (amends ADR 0088).
  - **niri** — the native `cursor { xcursor-theme "Bibata-Modern-Ice";
    xcursor-size 24; }` node in `config.kdl`.
  - **Hyprland** — `env = HYPRCURSOR_THEME,Bibata-Modern-Ice` +
    `HYPRCURSOR_SIZE,24` (primary), with `XCURSOR_THEME` kept as the XWayland /
    legacy fallback.
  - `~/.icons/default/index.theme` `Inherits=Bibata-Modern-Ice` seeded on all
    three so GTK / XWayland apps agree.

## Considered options

- **`bibata-cursor-theme-bin`** (prebuilt, Xcursor-only) — rejected: no
  hyprcursor, so Hyprland would only ever fall back to the Xcursor Bibata; misses
  the explicit hyprcursor requirement.
- **One fleet-wide entry in `hosts/core`'s `aur`** — rejected: installs the
  cursor even on headless/minimal hosts that have no cursor; the DE layer is the
  right home.

## Consequences

- `bibata-cursor-git` is a `-git` source build in the paru pass (slower than a
  prebuilt), accepted because it is the only package delivering both formats.
- KDE's seeded cursor changes from Breeze to Bibata Modern Ice (amends ADR
  0088); the rest of the Breeze Dark look is unchanged.
