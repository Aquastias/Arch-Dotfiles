# 01 — Bibata Modern Ice default on KDE

**What to build:** a fresh KDE box uses Bibata Modern Ice as its cursor instead
of Breeze. The KDE adapter installs `bibata-cursor-git` (via its `aur` list, the
Primary-User paru pass) and seeds `Bibata-Modern-Ice` as the cursor theme in the
KDE input config plus the standard default-icon path, at size 24. The rest of
the Breeze Dark look is unchanged.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] `bibata-cursor-git` is declared in the KDE adapter's `aur` list and lands
      via the paru pass when KDE is selected.
- [x] The seeded KDE input config sets the cursor theme to `Bibata-Modern-Ice`
      (replacing `breeze_cursors`), and `~/.icons/default` inherits it.
- [x] Cursor size is 24; the rest of the seeded Breeze Dark look is untouched.
- [x] `kde-adapter.bats` asserts the new cursor theme and the aur declaration.

## Comments

- 2026-09-27 audit: 7598539 (install-kde.jsonc aur, skel kcminputrc
  cursorTheme/cursorSize 24, kde.sh ~/.icons/default; kde-adapter.bats).
