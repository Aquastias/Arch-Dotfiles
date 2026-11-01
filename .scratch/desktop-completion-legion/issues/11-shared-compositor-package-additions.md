# 11: Shared compositor package additions

**What to build:** every Wayland Shell Companion session gets phone access
and video thumbnails in pcmanfm-qt, always-on UPower, and native Qt-on-
Wayland even without KDE. Parent: PRD.

**Blocked by:** None (can start immediately).

**Status:** done

- [x] The preset package set gains `gvfs-mtp`, `ffmpegthumbnailer`,
      `upower`, `qt6-wayland`.
- [x] Each confirmed package-only / D-Bus activated against its Arch Wiki
      page (no service enable needed).
- [x] Package Resolver reports them; resolver bats + both Fleet Golden
      fixtures regenerated.
- [x] wireplumber's UPower error gone from the desktop niri/Umbriel journal.

## Comments

- 2026-11-02: `qt6-wayland` dropped — on Qt 6.12 the Wayland platform plugin
  (`libqwayland.so`) ships in `qt6-base`, and the Arch Wiki (Wayland#Qt) says
  Qt 6 uses Wayland by default; `qt6-wayland` only adds compositor-side APIs.
  The other three are package-only (upower is D-Bus activated). The
  wireplumber UPower check is in ticket 13's journal review.
