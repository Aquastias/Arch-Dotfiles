# Kitty shipped fleet-wide (seeded + stowable), follows Noctalia

---
Status: accepted. Reuses the pi/zsh delivery + theme-template pattern (ADR
0127/0128/0129); default palette per ADR 0109; never-stow-a-generated-file per
ADR 0104/0108.
---

Kitty is the fleet terminal (core `packages.shell` + the [[Wayland Shell
Companion]] preset, ADR 0090) but its config was **stow-only**: no program
seeded it, so a fresh box ran stock kitty unless the operator stowed by hand —
unlike pi and zsh, which seed **and** stow. Separately, the committed config
carried a dead **Nord** palette in `conf/color-scheme.conf`/`conf/cursor.conf`
overridden by a final `include themes/catppuccin-mocha.conf`, and set
`font_family Fira Code Bold` — a face **not installed anywhere on the fleet**
(the fleet ships `ttf-meslo-nerd`), so kitty fell back to default mono and
Nerd-Font glyphs in the p10k prompt broke. We want kitty served at install,
hand-stowable, and following a live Noctalia palette change exactly as the pi
TUI does (ADR 0128).

## Decision

**Delivery — a `system/kitty` [[User Program]].** Mirrors `system/zsh`: seeds
the full kitty config (bundled `home/.config/kitty/`, kept byte-identical to the
repo stow tree by a drift test) into the owning user's `$HOME` **and**
`/etc/skel` — the installer never stows (ADR 0095), so a non-stowing user still
gets a working terminal; the repo copy stays hand-stowable. The program **owns
the `kitty` package** (plus the font `ttf-firacode-nerd`, so `font_family
FiraCode Nerd Font` keeps the Fira Code look *and* renders Nerd glyphs): a
Categorized-List package entry may not also name a Program (Program/package
exclusivity, ADR 0115), so `kitty` **leaves core `packages.shell`** for this
program — the same shape as `docker`/`virt-manager`. The Noctalia preset's own
package list (a bash function, not a Categorized List) still carries `kitty` so
a compositor box has its terminal even for a user who excludes the program.

**Theme-follow — a Noctalia user-template, not the builtin.** Noctalia's builtin
`kitty` template renders the palette into `~/.config/kitty/themes/noctalia.conf`
**and its `apply.sh` rewrites `kitty.conf`** to inject the include. That `mv`
over `kitty.conf` would clobber a **stow symlink** and push the include into the
repo — the exact generated-vs-stowed dirt ADR 0104/0108 bans. So we **drop
`"kitty"` from `[theme.templates].builtin_ids`** and add a user-template
`[theme.templates.user.kitty]`: input `$XDG_CONFIG_HOME/noctalia/templates/
kitty.conf` (static, stowed, Mustache — the same `terminal_*`/Material role
mapping the builtin uses), output `~/.config/kitty/themes/noctalia.conf`. The
committed `kitty.conf` carries `include themes/noctalia.conf` itself. Kitty
auto-reloads its config on change by default (VM-verified: a running window
repaints on write) — so like pi, **no `post_hook` and no [[Live Theme Bridge]]
change** is needed. (`auto_reload_config` is **not** a kitty option — setting it
is a parse error; the default watch is what does the work.)

The generated `noctalia.conf` is **seeded with Catppuccin Mocha Sapphire** (ADR
0109) by the kitty program and live-rewritten **only in compositor sessions** —
niri/Hyprland follow live, KDE (no template run) stays on the seed, matching the
[[App Theming Bridge]] isolation. It is **seed-only, never stowed**: the whole
`.config/kitty/themes/` dir is gitignored (as `.zsh/themes/` is), and
`stow --no-folding` keeps `~/.config/kitty` a real dir so Noctalia writes
`themes/noctalia.conf` beside the symlinked part-files without dirtying the
repo.

**Color ownership.** `noctalia.conf` (included last) owns **all** terminal
color. Every color knob it sets is stripped from the split `conf/*.conf` —
foreground/background/palette/selection (`color-scheme.conf`), cursor color
(`cursor.conf`), `url_color` (`mouse.conf`), active/inactive border
(`window-layout.conf`), tab fg/bg (`tab-bar.conf`) — and the four static
`themes/catppuccin-*.conf` are deleted (mirroring ADR 0129 dropping the static
Catppuccin zsh files). Non-color knobs stay put.

**Config knobs (operator-reviewed).** `background_opacity 1.0` (opaque —
transparency was tried and rejected: on this dark theme it only tinted the
terminal toward the purple wallpaper bleeding through, hurting readability;
VM-verified) and
`cursor_shape beam` kept; `env.conf` (`env LS_COLORS=$LS_COLORS`) dropped from
the include list (the shell owns `LS_COLORS`); `tab_bar_min_tabs 2` (hide the
bar for a single tab); `hide_window_decorations yes` (no client-side titlebar —
the operator disliked the toolbar; clean on a tiling WM) with
`wayland_titlebar_color system` (moot once hidden, but neutral if re-enabled);
`active_border_color` left to the Noctalia accent; font size 12, `bold_font
auto`. Everything else (scrollback, bell, keybinds, padding,
confirm-close) is unchanged kitty behavior.

## Considered options

- **Keep the builtin `kitty` template** and pre-place the include so `apply.sh`
  is a no-op — rejected: `apply.sh` still `mv`s over `kitty.conf`, turning the
  stow symlink into a divergent regular file. A user-template never touches a
  stowed file, exactly as pi/zsh do.
- **A config-only program, leaving `kitty` in core `packages.shell`** — rejected
  as *invalid*: Program/package exclusivity (ADR 0115) forbids a Categorized-
  List entry that names a Program, so the moment `system/kitty` exists, `kitty`
  must leave `packages.shell`. The program therefore owns the package (like
  `docker`/`virt-manager`); the preset's non-list `kitty` is exempt and stays.
- **Keep `Fira Code Bold` + install plain `ttf-firacode`** — rejected: no Nerd
  glyphs, so the p10k prompt icons stay broken; the Nerd variant is the point.
- **Keep the static Catppuccin theme files** — rejected: they don't follow the
  palette; `noctalia.conf` supersedes them (ADR 0129 precedent).

## Consequences

- Kitty is themed and follows the palette on every fresh install — live on the
  compositors, fixed on the seeded Mocha Sapphire under KDE.
- The default palette now lives in one more seed point (kitty's
  `noctalia.conf`); an ADR 0109 default change must update it too, beside
  pi/zsh.
- `.config/kitty/themes/` is gitignored; a bare stow user *without* the
  installer has `include themes/noctalia.conf` pointing at an absent file (kitty
  warns and continues) — the same seed-only limit `.zsh/themes/` already has;
  the fleet always installs, so this is the un-run path only.
- New fleet surface: a `system/kitty` program, a `templates/kitty.conf` input
  (rides the preset's existing `templates/*` seed), one `ttf-firacode-nerd`
  package, and a byte-identical drift test (repo `.config/kitty/` ↔ program
  `home/`) in `kitty-program.bats`, plus `noctalia-stow.bats`/`configs.bats`
  guards.
