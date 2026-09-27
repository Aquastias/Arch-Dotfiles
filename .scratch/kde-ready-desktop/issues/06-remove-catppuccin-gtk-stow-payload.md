# 06 — Remove Catppuccin GTK from stow payload

**What to build:** The desktop is coherently dark instead of mixing a
Breeze Dark Plasma with Catppuccin GTK apps. The Catppuccin GTK theming
is removed from the stow payload (`.config/gtk-3.0`, `.config/gtk-4.0`),
and `settings.ini` is rewritten to the Breeze / Papirus-Dark /
Breeze-cursors defaults so GTK apps follow the dark look installed in
ticket 03 (`breeze-gtk` / `kde-gtk-config`). Catppuccin is re-addable
later — this only removes it for now.

**Blocked by:** 03 — GTK-dark actually applies only once `breeze-gtk` /
`kde-gtk-config` are installed there.

**Status:** done

- [x] Catppuccin GTK theme assets/config are removed from
      `.config/gtk-3.0` and `.config/gtk-4.0`
- [x] `settings.ini` names the Breeze GTK theme, `Papirus-Dark` icons,
      and Breeze cursors
- [x] No Catppuccin reference remains in the GTK stow payload
- [x] The removal is self-contained and reversible (Catppuccin can be
      re-added later without structural change)

## Comments

- 2026-09-27 doc sync: shipped in b425758, 3ef89ef, f8fdf38, 0e5486a, 6af9f0e,
  6878699, 0bd152f, f43fabe (ADR 0087/0088).
