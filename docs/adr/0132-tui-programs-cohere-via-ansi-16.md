# TUI programs cohere via the terminal's 16 ANSI colors

---
Status: accepted. Extends the theming cluster (ADR 0102/0116/0128/0129/0130);
default palette per ADR 0109; program/package exclusivity ADR 0115;
never-stow-a-runtime-rewritten-file per ADR 0104/0108. Neovim excluded.
---

Kitty now ships following Noctalia (ADR 0130), but the rest of the fleet's
shipped color CLIs/TUIs do not cohere. `eza` renders on its own built-in
palette; `lazygit` and `yazi` are stock; `.p10k.zsh` still hardcodes two
Catppuccin Mocha hexes (root/context); `htop` is stock. None of them follows a
Noctalia palette change on the wl-roots compositors, and none is guaranteed to
sit on the fleet default (Catppuccin Mocha Sapphire, ADR 0109) under KDE. Only
`fzf`, `zsh-syntax-highlighting` (both via the [[Zsh Theme Template]]), `pi`
(ADR 0128), `btop` (Noctalia builtin) and the p10k **accent** already follow.

The realization that makes this cheap: **kitty's generated `noctalia.conf`
already owns the terminal's 16 ANSI colors** (ADR 0130) and makes them follow
the live palette on the compositors while sitting on the seeded Sapphire under
KDE. So **any TUI rendered through those 16 ANSI slots is automatically
cohesive on both session classes**, for free — no new Noctalia template, no new
ADR-0109 seed point. This is exactly the `BAT_THEME=ansi` trick already noted in
ADR 0129: the terminal is the single seam.

## Decision

**ANSI-16-first.** Point every shipped color CLI/TUI at the terminal's 16 ANSI
colors (plus its own default fg/bg), never at hex. One seam — kitty's palette —
carries all of them; live-follow on the compositors and Sapphire-under-KDE both
fall out of it. A per-app Noctalia **[[Pi Theme Template]]**-style hex template
stays the **fallback**, used only for a tool that cannot express color through
the 16 ANSI slots (needs 256/truecolor). None of the current set does.

Per tool:

- **`eza`** → an ANSI-16 `EZA_COLORS` export added to the `system/zsh` program
  (`.zsh/env/exports.zsh`), riding its existing seed **and** stow. It covers the
  fields `LS_COLORS` does not (permissions, size, date, git), which is why eza
  looked off-palette despite the `dircolors -b` `LS_COLORS`. Re-read per
  invocation.
- **`lazygit`** → a new seeded **and** stowable `system/lazygit` [[User
  Program]] carrying a `gui.theme` in ANSI color **names** (`red`, `green`, …,
  `default`). It **owns the `lazygit` package**, which therefore leaves core
  `packages.shell` (Program/package exclusivity, ADR 0115), and gets a
  byte-drift test — the `system/kitty`/`system/zsh` shape. Restart-only (lazygit
  reads config at startup).
- **`yazi`** → a new seeded **and** stowable `system/yazi` [[User Program]]
  carrying a `theme.toml` in yazi's **named** ANSI colors (it accepts names, not
  numeric indices). Owns the `yazi` package (leaves `packages.shell`, ADR 0115),
  byte-drift test. Restart-only.
- **`.p10k.zsh`** → the two hardcoded Catppuccin Mocha hexes on the root/context
  segments are remapped to **ANSI-16 red/yellow** — semantically correct
  (warning), follows the palette live via the terminal, and removes the last
  stray hardcoded hex in the prompt. No new key in the `p10k-accent` template.
- **`htop`** → left stock. `color_scheme=0` (Default) already renders through
  the terminal ANSI palette, and `htoprc` is **runtime-rewritten** by htop, so
  stowing it would clobber/dirty the repo (the generated-file ban, ADR 0104) —
  a non-stowable file for one line is not worth it.
- **`bat`** → `BAT_THEME=ansi` stays as-is: latent (bat is not installed by any
  profile), harmless, and correct the moment bat ever ships.
- **`git` diff / `less` / `ripgrep` / `fd`** → already render default ANSI;
  verified, no change.

**Neovim is out of scope.** It is a full editor with its own colorscheme
universe (a deliberate rose-pine, ADR 0093-era), not ANSI-driven; forcing it
onto Sapphire/Noctalia-follow is a disproportionate, separate effort.

The lazygit/yazi configs are **static, not Noctalia-generated** — nothing
rewrites them at runtime — so unlike the [[Kitty Theme Template]] outputs they
are plainly **stowed and seeded**, with no gitignore/seed-only dance.

## Considered options

- **A per-app Noctalia hex template for each tool** (the pi/zsh/kitty pattern) —
  rejected: N new templates and N new ADR-0109 seed points, all duplicating
  colors the terminal's 16 ANSI slots already carry. ANSI-16 is one seam that
  also hands us KDE isolation for free. Templates remain the fallback for a tool
  that genuinely can't do ANSI.
- **Static Catppuccin Mocha Sapphire theme files per tool** — rejected: they do
  not follow a palette change on the compositors (defeating the goal) and
  duplicate the palette. This was the Q4 fallback; it was never reached because
  all four tools do ANSI-16.
- **Stow-only configs for lazygit/yazi** (no seed) — rejected: a non-stowing
  fresh box would run them stock, unlike kitty/pi/zsh which seed **and** stow.
  Operator chose seed+stow for fleet-wide default.
- **Include neovim** — rejected: separate theming universe, deliberate
  rose-pine.
- **Seed or stow an `htoprc`** — rejected: Default already tracks the ANSI
  palette, and htop rewrites `htoprc` on clean exit, so a stow symlink dirties
  the repo and a seed is one line for zero gain.

## Consequences

- Every shipped color TUI **except neovim** now follows a Noctalia palette
  change live on the compositors and sits on Catppuccin Mocha Sapphire under
  KDE — through **one seam** (the terminal's 16 ANSI colors), with **no new
  Noctalia template and no new ADR-0109 seed point**.
- Repaint follows each tool's own reload model: `eza`/`fzf` on next render;
  `lazygit`/`yazi` and the p10k body on next launch — the bounded, relaunch-only
  limit the [[Zsh Theme Template]] already documents.
- Two new [[User Program]]s (`system/lazygit`, `system/yazi`); `lazygit` and
  `yazi` leave core `packages.shell` (ADR 0115); each gains a byte-drift test
  (the kitty/zsh precedent).
- `system/zsh` gains an `EZA_COLORS` export; the two hardcoded Catppuccin hexes
  in `.p10k.zsh` are gone.
- **New rule for future terminal-tool additions:** default to ANSI-16 following;
  reach for a Noctalia user-template only when the tool cannot express color
  through the terminal's 16 slots.
