# 08: pcmanfm-qt answers "Show in folder"

**What to build:** in niri, Hyprland and Umbriel, "Show in folder" from a
browser or Electron app opens pcmanfm-qt, not Dolphin. `Super+E` still opens
pcmanfm-qt windows; Plasma keeps Dolphin. Parent: PRD (ADR 0162).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] Each compositor's curated autostart starts `pcmanfm-qt -d`.
- [x] Stow bats assert the entry in all three curated configs.
- [x] Feature Audit probe: the `org.freedesktop.FileManager1` owner is
      pcmanfm-qt in each wlroots session.
