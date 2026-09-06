# 02 — GTK3 live-repaint nudge

**What to build:** extend the [[Live Theme Bridge]] so a mid-session theme change
also repaints **running GTK3** apps without a relaunch. On each color-file
change the bridge additionally performs a transient `gsettings` `gtk-theme`
toggle — the minimal poke that makes `kde-gtk-config`'s `colorreload-gtk-module`
fire (a palette change alone does not: the theme name stays `adw-gtk3-dark` and
only `noctalia.css` content changes, so the module never triggers on its own).
This is a runtime-only change to the existing script — no new committed payload —
so acceptance is by hand on the VM, per the repo's no-runtime-test model.
GTK4/libadwaita stays relaunch-only for palette colors by design (ADR 0116);
mode still follows live.

**Blocked by:** 01 — Live Theme Bridge scaffolding + Qt6 live-repaint (the shared
script and its watch loop must exist).

**Status:** ready-for-agent

- [ ] On a color-file change the bridge performs a transient `gsettings`
      `gtk-theme` toggle that fires `colorreload-gtk-module`; a running GTK3 app
      repaints to the new palette without relaunch — verified by hand on the
      `arch-combined` VM.
- [ ] The toggle returns `gtk-theme` to `adw-gtk3-dark` and produces no visible
      flash / no lingering wrong theme name (tune the exact toggle on the VM).
- [ ] No new persistent write Plasma reads-and-does-not-reset: the toggle touches
      only shared theme-name/dconf that `kde-gtk-config` reasserts to Breeze on
      Plasma login — Plasma stays deterministically Breeze on a combined box.
- [ ] GTK4 palette repaint is explicitly NOT attempted; dark/light on GTK4 keeps
      following live via libadwaita's own portal subscription.
