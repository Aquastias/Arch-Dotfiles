# Pi TUI follows Noctalia via a native user-template

---
Status: accepted. Extends the theming cluster (ADR 0102/0116); default palette
per ADR 0109.
---

The pi TUI should follow a mid-session Noctalia palette change on the
compositors, while staying fixed under KDE (which keeps Breeze, ADR 0104). Pi
themes are JSON files of 53 color tokens, and **pi hot-reloads the active theme
file when it changes on disk**. Noctalia supports **user-defined templates**
(`[theme.templates.user.*]`) that render the live palette into an arbitrary
output file. That pairing gives theme-follow with no new moving parts.

## Decision

Ship a Noctalia **user-template** `[theme.templates.user.pi]` that renders the
resolved palette's 16 Material roles into pi's 53 tokens, writing
**`~/.pi/agent/themes/noctalia.json`**. Pi is configured with `theme:
"noctalia"` and hot-reloads that file on write — so **no `post_hook` and no
change to the [[Live Theme Bridge]]** is required.

The single `noctalia.json` file is **seeded with Catppuccin Mocha Sapphire**
values (the fleet default, ADR 0109) and live-rewritten **only in compositor
sessions** (niri/Hyprland run Noctalia's template engine). KDE never runs the
template, so under KDE the file stays on the seeded Catppuccin Mocha Sapphire —
one file satisfies the default, KDE-no-follow, and compositor-live-follow at
once, matching the [[App Theming Bridge]]'s compositor isolation.

Because Noctalia rewrites it, `noctalia.json` is **seed-only — never stowed**
(ADR 0104): it is gitignored (`.pi/agent/themes/`) and delivered by the program
seed into the user's home, so a stow symlink can never push a live repaint back
into the repo. The **template input file** (`~/.config/noctalia/templates/
pi.json`, Mustache `{{colors.<role>.default.hex}}`) is static and *is* stowed;
semantic colours (success/warning/diff) map to the palette's `terminal_*` roles
since Material You exposes no green/yellow accent role.

## Considered options

- **Extend `noctalia-theme-bridge` to regenerate the pi theme** — rejected: a
  native user-template is idiomatic to the existing template stack (`kitty`,
  `niri`, …), needs no binary edit, and survives bridge rewrites.
- **Hand-generate a static pi theme JSON per Noctalia palette** (10 builtins +
  105 community) — rejected: live-follow already matches whatever palette is
  active, so ~115 static files earn nothing and rot.
- **`pi --use-theme light/dark`** — rejected: follows only terminal light/dark,
  not the actual palette.

## Consequences

- Under KDE the pi TUI is Catppuccin Mocha Sapphire and does not follow the
  session theme, by design.
- Changing any Noctalia palette on a compositor repaints the pi TUI live without
  restart.
- The default palette now lives in one more place (the seeded `noctalia.json`);
  a default change must update it alongside the ADR 0109 seed points.
