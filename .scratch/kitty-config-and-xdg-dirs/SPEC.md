# Spec: Kitty served + stowable + Noctalia-following, and XDG dirs on wl-roots

Status: ready-for-agent

Traces to ADR 0130 (kitty fleet-wide, seeded + stowable, follows Noctalia) and
ADR 0131 (XDG user dirs generated on wl-roots sessions). Glossary: [[Kitty
Config]], [[Kitty Theme Template]], [[Wayland Session XDG Dirs]].

## Problem Statement

Two gaps on the wl-roots (niri/Hyprland) side of the fleet:

1. **Kitty is unthemed and under-delivered.** The kitty config is stow-only, so
   a fresh box runs stock kitty unless the operator stows by hand — unlike
   pi/zsh, which seed **and** stow. Its committed colors are a dead Nord palette
   overridden by a Catppuccin include, it does not follow a live Noctalia
   palette change, and its `font_family` (`Fira Code Bold`) is not installed on
   the fleet, so Nerd-Font glyphs in the shell prompt break.
2. **XDG user dirs are missing under niri/Hyprland.** `~/Desktop`,
   `~/Downloads`, … exist under KDE but not on the compositors, and there is no
   `~/Projects`.

## Solution

1. Kitty is themed and delivered exactly as pi/zsh are: a [[User Program]] seeds
   the full config into `$HOME` + `/etc/skel` and the repo copy stays
   hand-stowable; a [[Kitty Theme Template]] makes the terminal follow a live
   Noctalia palette change on the compositors while staying fixed on the seeded
   Catppuccin Mocha Sapphire under KDE. The font is fixed to an installed Nerd
   variant so prompt glyphs render.
2. On login to a niri/Hyprland session the standard XDG user dirs and a
   `~/Projects` folder are generated ([[Wayland Session XDG Dirs]]); KDE is
   unchanged (it already generates them).

## User Stories

1. As an operator on a fresh niri box, I want kitty to open already themed, so I
   don't stare at stock white kitty on first login.
2. As an operator, I want kitty's config seeded into my `$HOME` at install, so a
   non-stowing user still gets a working, themed terminal.
3. As an operator, I want the same kitty config to remain hand-stowable from the
   repo, so my personal machine tracks the repo as the single source.
4. As an operator, I want the seeded config kept byte-identical to the repo stow
   tree, so the two never silently drift.
5. As a user on a compositor, I want kitty to repaint live when I change the
   Noctalia palette, so the terminal matches the rest of the desktop instantly.
6. As a user under KDE, I want kitty to stay on the fixed default palette, so it
   matches KDE's Breeze-fixed app-theming isolation rather than following a
   compositor-only palette.
7. As a user, I want the terminal's 16 ANSI colors, background, foreground,
   cursor, selection, borders and tab colors all driven by the palette, so no
   element is left on a stale hardcoded color.
8. As a maintainer, I want a single source of truth for terminal color, so I
   never have to reconcile a Nord block against a Catppuccin include again.
9. As a user, I want the shell prompt's Nerd-Font glyphs to render in kitty, so
   Powerlevel10k segments aren't broken boxes.
10. As a maintainer, I want the kitty package owned in exactly one place (the
    program, not also a package list), so the package graph stays coherent under
    Program/package exclusivity.
11. As a user, I want the terminal to reload its colors on write with no manual
    step, so a palette change needs no restart or keypress.
12. As a user, I want the built-in Noctalia kitty template's config-rewriting
    behavior disabled, so it never clobbers my stowed `kitty.conf`.
13. As a user reviewing the config, I want the transparency (0.7),
    tab-bar-hides-when-single, hidden-window-decorations and single-source-color
    choices applied, so the terminal matches the reviewed decisions.
14. As a user on a niri/Hyprland session, I want `~/Desktop`, `~/Downloads`,
    `~/Documents`, `~/Music`, `~/Pictures`, `~/Videos`, `~/Templates`,
    `~/Public` generated on login, so apps have their standard destinations.
15. As a developer, I want a `~/Projects` folder created and resolvable via an
    `XDG_PROJECTS_DIR` entry, so tooling can find my projects dir.
16. As a user, I want XDG-dir generation to be idempotent, so repeated logins
    don't churn or duplicate anything.
17. As a user under KDE, I want no change to XDG-dir behavior, so the compositor
    fix never double-runs or interferes under Plasma.
18. As a maintainer, I want the XDG fix launched from the compositor autostart
    (not a systemd-user unit), so it reliably reaches Hyprland's non-uwsm
    session.
19. As a maintainer, I want the default-palette seed point for kitty tracked
    with the other ADR-0109 seed points, so a default change updates all of
    them.

## Implementation Decisions

- **Delivery.** A new `kind: user` [[User Program]] `system/kitty` seeds the
  full [[Kitty Config]] into `$HOME` and `/etc/skel`, byte-identical to the repo
  stow tree, and stays hand-stowable — the pi/zsh delivery pattern (ADR
  0127/0130, installer-never-stows ADR 0095). It also seeds the default
  generated theme file (Catppuccin Mocha Sapphire) into `$HOME`, `/etc/skel`,
  and `/root`, matching the zsh theme-seed. The program is registered in **User
  Core `programs`** so it reaches the fleet like pi (ADR 0114).
- **Package ownership.** The program **owns the `kitty` package** plus the font
  (`ttf-firacode-nerd`, `extra`, provides `ttf-font-nerd`): Program/package
  exclusivity (ADR 0115) forbids a Categorized-List entry that also names a
  Program, so `kitty` leaves core `packages.shell` for this program (as
  `docker`/`virt-manager` do). The [[Wayland Shell Companion]] preset's non-list
  package set still carries `kitty` for the compositor terminal.
- **Theme-follow.** Drop `"kitty"` from Noctalia's `builtin_ids` and add a
  user-template `[theme.templates.user.kitty]` ([[Kitty Theme Template]]) whose
  static Mustache input maps the palette's `terminal_*`/Material roles into
  kitty color and whose output is the generated theme file that `kitty.conf`
  `include`s. Rationale: the builtin's `apply.sh` rewrites `kitty.conf` and
  would clobber the stow symlink; a user-template only writes its output. The
  generated output is **seed-only, never stowed** (its whole themes dir is
  gitignored); the template input is stowed and rides the preset's existing
  `templates/*` seed. Kitty auto-reloads its config on change by default
  (VM-verified), so a running window repaints on write — no `post_hook`, no
  [[Live Theme Bridge]] change, exactly as pi.
- **Color ownership.** The generated theme file (included last) owns all
  terminal color. Every color knob it sets is stripped from the split config
  part-files, and the static Catppuccin theme files are deleted. Non-color knobs
  stay.
- **Reviewed config knobs.** `background_opacity 0.7` (subtle, readable) and
  `cursor_shape beam` kept; drop the `LS_COLORS` env pass-through part-file from
  the include list; hide the tab bar for a single tab; hide client-side window
  decorations (no toolbar; titlebar colour left `system`); let the active-window
  border follow the accent; font at the reviewed size with automatic bold.
  Scrollback, bell, keybinds,
  padding and confirm-close are unchanged kitty behavior.
- **XDG dirs.** A seeded `noctalia-xdg-user-dirs` script (riding the [[Wayland
  Shell Companion]] preset's `.local/bin/noctalia-*` skel seed) is called from
  the per-compositor autostart part-files. It runs `xdg-user-dirs-update` — the
  standard set, created from the stock English `/etc/xdg/user-dirs.defaults` for
  a user with no `user-dirs.dirs` yet — then creates `~/Projects` and appends a
  non-standard `XDG_PROJECTS_DIR`. Run at login as the user, it reaches existing
  and new users alike (no per-`$HOME` preset seed; the preset is skel-only, ADR
  0095). Compositor-scoped — KDE already generates the dirs via
  `/etc/xdg/autostart/`.

## Testing Decisions

Good tests here assert **external behavior at the delivery and theming seams**,
not file contents line-by-line. Prefer existing seams; the ideal is to add no
new seam.

- **Drift seam (new file, existing pattern).** A byte-identical drift test keeps
  the program's seeded `home/` equal to the repo stow tree — the zsh precedent,
  which lives in `zsh-program.bats`, so kitty's lives in a sibling
  `kitty-program.bats` (not `configs.bats`, which only carries the User Core
  `programs` list assertion). This is the single highest seam for
  "seeded == stowed".
- **Program-definition seam.** `kitty-program.bats` also asserts the program
  shape (config.jsonc kind; install.sh installs kitty + the Nerd font and seeds
  `$HOME`/`/etc/skel`/`/root` + the default theme) and the seed default palette.
- **Preset/theme-wiring seam (existing).** Extend `noctalia-stow.bats` to
  assert: `"kitty"` is absent from `builtin_ids`; the `kitty` user-template is
  declared with the right input/output; `kitty.conf` includes the generated
  theme; and the `noctalia-xdg-user-dirs` script + both per-compositor autostart
  entries exist.
- **End-to-end seam (existing).** The arch-combined VM is the established seam
  for live theme-follow and fresh-install delivery (ADR 0108/0116 were verified
  this way). Verify: kitty opens themed on first login; a Noctalia palette
  change repaints a running kitty live on the compositor; kitty stays fixed
  under KDE; and the XDG dirs incl. `~/Projects` exist after a niri/Hyprland
  login.

## Out of Scope

- Any change to KDE's XDG-dir behavior or app theming (already correct).
- A full role-mapped port of the p10k prompt (tracked by ADR 0129).
- Live GTK palette repaint limits on native Wayland (bounded by ADR 0116).
- Extending the [[Live Theme Bridge]] — deliberately not needed here.
- Terminal choice / adding kitty to any new package list.

## Further Notes

- The default palette now has one more seed point (kitty's generated theme
  file); an ADR-0109 default change must update it beside pi/zsh and the qt6ct
  snapshot.
- A bare stow user *without* the installer will have an `include` of an absent
  generated theme file (kitty warns, continues) — the same seed-only limit
  `.zsh/themes/` already has; the fleet always installs.
