# 28: Visual review of the screenshot gallery

**What to build:** Open every screenshot of the zero-Finding run;
theming/layout breakage (wrong colours, unthemed Qt/GTK app, missing
bar/wallpaper) becomes a Finding with its own ticket.

**Blocked by:** 27

**Status:** done

- [x] Every screenshot reviewed; result noted in Comments

## Comments

**2026-10-09 — Run 20261008-191424.** No zero-Finding run exists, so the
review used the final run (user-agreed). 59 screenshots, no duplicates
(the hung-GTK signature).

- base, desktop, greetd, laptop, tuned: niri, Hyprland and KDE themed
  consistently.
- Dolphin (Qt) and nm-connection-editor (GTK) are themed in every desktop.
- The bar and wallpaper are present.
- hyprland-pure, kde-pure, niri-pure, and no-shell's compositors show stock
  welcome screens and configs. That's by design (ADR 0097/0112: a bare
  compositor seeds nothing).
- efistub and ufw consoles show the boot that ticket 29 tracks.

No visual Findings.
