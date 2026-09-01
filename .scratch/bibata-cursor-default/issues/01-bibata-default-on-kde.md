# 01 — Bibata Modern Ice default on KDE

**What to build:** a fresh KDE box uses Bibata Modern Ice as its cursor instead
of Breeze. The KDE adapter installs `bibata-cursor-git` (via its `aur` list, the
Primary-User paru pass) and seeds `Bibata-Modern-Ice` as the cursor theme in the
KDE input config plus the standard default-icon path, at size 24. The rest of
the Breeze Dark look is unchanged.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `bibata-cursor-git` is declared in the KDE adapter's `aur` list and lands
      via the paru pass when KDE is selected.
- [ ] The seeded KDE input config sets the cursor theme to `Bibata-Modern-Ice`
      (replacing `breeze_cursors`), and `~/.icons/default` inherits it.
- [ ] Cursor size is 24; the rest of the seeded Breeze Dark look is untouched.
- [ ] `kde-adapter.bats` asserts the new cursor theme and the aur declaration.
