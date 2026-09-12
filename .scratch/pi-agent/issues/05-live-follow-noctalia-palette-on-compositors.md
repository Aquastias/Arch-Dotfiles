# 05: Live-follow Noctalia palette on compositors

**What to build:** On niri/Hyprland, changing the Noctalia palette repaints the
pi TUI live; under KDE the pi TUI stays Catppuccin Mocha Sapphire. No change to
the Live Theme Bridge is needed — pi hot-reloads its active theme file.

Scope: declare a Noctalia user-template `[theme.templates.user.pi]` in the
Wayland Shell Companion's `config.toml` and ship its template input file
(Mustache `{{colors.<role>.default.hex}}`, `.hex_stripped` where a `#` must drop)
that renders the live palette's Material roles into pi's 53 tokens at
`~/.pi/agent/themes/noctalia.json`. The template runs only in compositor
sessions, so KDE never rewrites the file and stays on the seeded Catppuccin Mocha
Sapphire (matching the App Theming Bridge isolation). No `post_hook` required.
Anchored by ADR 0128.

**Blocked by:** 04 (needs the seeded `noctalia.json` target + `theme: "noctalia"`).

**Status:** ready-for-agent

- [ ] `config.toml` declares `[theme.templates.user.pi]` rendering to
      `~/.pi/agent/themes/noctalia.json`.
- [ ] The template input file maps the palette's Material + terminal roles to
      pi's 53 tokens.
- [ ] The template runs only in niri/Hyprland sessions, never under KDE.
- [ ] `pi-agent.bats` asserts `config.toml` declares the pi user-template.
- [ ] On `arch-combined`, `session niri` + a Noctalia palette change repaints the
      pi TUI; `session kde` leaves it on Catppuccin Mocha Sapphire.
