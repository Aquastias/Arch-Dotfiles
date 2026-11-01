# 11: Shared compositor package additions

**What to build:** every Wayland Shell Companion session gets phone access
and video thumbnails in pcmanfm-qt, always-on UPower, and native Qt-on-
Wayland even without KDE. Parent: PRD.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The preset package set gains `gvfs-mtp`, `ffmpegthumbnailer`,
      `upower`, `qt6-wayland`.
- [ ] Each confirmed package-only / D-Bus activated against its Arch Wiki
      page (no service enable needed).
- [ ] Package Resolver reports them; resolver bats + both Fleet Golden
      fixtures regenerated.
- [ ] wireplumber's UPower error gone from the desktop niri/Umbriel journal.
