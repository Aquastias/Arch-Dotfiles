# 02 — GTK repaint nudge (best-effort; Wayland palette is relaunch-only)

**What to build:** extend the [[Live Theme Bridge]] with a GTK nudge on each
color-file change. **Finding from VM testing (ADR 0116):** a running *native
Wayland* GTK app cannot be made to re-read its palette — the palette lives in the
load-once user `gtk.css` (`@import noctalia.css`), and `kde-gtk-config`'s
`colorreload-gtk-module` is an X11 mechanism inert under native Wayland (a
Wayland `nm-connection-editor` stayed on its launch-time Catppuccin palette
through Gruvbox and Nord). So GTK palette is **relaunch-only on Wayland**. The
bridge keeps a transient `gsettings` `gtk-theme` **read-toggle-restore** as a
**best-effort** nudge: it *does* repaint XWayland/X11 GTK apps, it preserves
whatever theme name Noctalia set (never forcing dark over light), and it is
harmless for native-Wayland apps. Dark/light still follows live for libadwaita
via the portal. GTK4 was always relaunch-only for palette.

**Blocked by:** 01 — Live Theme Bridge scaffolding + Qt6 live-repaint.

**Status:** ready-for-agent

- [ ] On a color-file change the bridge performs a `gsettings` `gtk-theme`
      read-toggle-restore: read the current name, set a transient alternate, then
      restore the original — never hardcoding `adw-gtk3-dark` (which would
      override Noctalia's light-mode choice).
- [ ] No new persistent write Plasma reads-and-does-not-reset: the toggle touches
      only shared theme-name/dconf that `kde-gtk-config` reasserts to Breeze on
      Plasma login — Plasma stays deterministically Breeze on a combined box.
- [ ] Docs state GTK palette is relaunch-only on native Wayland (ADR 0116 /
      spec / `CONTEXT.md`); no brittle app-restart hack is attempted.
- [ ] Dark/light on libadwaita keeps following live via the portal (unchanged).
