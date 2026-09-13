# Zsh follows Noctalia via user-templates

---
Status: accepted. Reuses the pi theme-template mechanism (ADR 0128); default
palette per ADR 0109. Depends on the `system/zsh` program (this change).
---

The interactive zsh shell (fzf, zsh-syntax-highlighting, Powerlevel10k) should
follow a Noctalia palette change on the compositors while staying fixed under
KDE, matching the pi TUI (ADR 0128). Unlike pi, **zsh does not hot-reload**:
`FZF_DEFAULT_OPTS`, `ZSH_HIGHLIGHT_STYLES`, and the p10k `*_FOREGROUND` values
are read at shell startup. So the surface a template can drive is limited to a
sourced file, and repaint is relaunch-only.

## Decision

Ship two Noctalia **user-templates** rendering the live palette into seed-only
files that `.zshrc` sources:

- `[theme.templates.user.zsh]` → `~/.zsh/themes/noctalia.zsh` —
  `FZF_DEFAULT_OPTS` + `ZSH_HIGHLIGHT_STYLES`, sourced by `.zshrc`.
- `[theme.templates.user.p10k-accent]` → `~/.zsh/themes/p10k-accent.zsh` —
  **only the accent-carrying p10k `*_FOREGROUND` keys** (dir/anchor/os-icon),
  sourced after `~/.p10k.zsh` so it wins. The rest of the 491-key `.p10k.zsh`
  stays fixed and committed.

Both files are **seeded with Catppuccin Mocha Sapphire** (ADR 0109) by the
`system/zsh` program and live-rewritten **only in compositor sessions** — KDE
never runs the template, so there zsh stays on the seed, exactly as pi does.
Being Noctalia-rewritten, the outputs are **seed-only, never stowed**: gitignored
(`.zsh/themes/`); the Mustache template inputs (`templates/zsh.zsh`,
`templates/p10k-accent.zsh`) are static and *are* stowed. Semantic colours map
to the palette's `terminal_*` roles, as in ADR 0128.

A running shell repaints on the **next shell / `zshreload`**, not mid-session —
the same relaunch-only limit the [[Live Theme Bridge]]'s KColorScheme apps have
(ADR 0124); env-var and prompt colour are simply not re-read live.

## Considered options

- **Live-follow the whole `.p10k.zsh`** — rejected: 491 keys, most unrelated to
  the accent; a full role-mapped port is large and fragile for little gain. An
  accent-only override gets the visible win cheaply. Starship (TOML, template-
  friendly) is the path if full prompt-follow is ever wanted — tracked separately.
- **One combined template emitting everything** — rejected: fzf/syntax and p10k
  are sourced at different points (`.zshrc` vs after `.p10k.zsh`); two outputs
  keep each sourced where it belongs.
- **Keep the static Catppuccin syntax/fzf theme files** — rejected: they don't
  follow the palette; the generated file supersedes them.

## Consequences

- Under KDE the shell is Catppuccin Mocha Sapphire and does not follow the
  session theme, by design.
- A palette change on a compositor repaints new shells; open shells need a
  `zshreload` / new shell — not automatic.
- The default palette now lives in one more place (the seeded zsh theme files);
  a default change must update them alongside the other ADR 0109 seed points.
- The p10k prompt only partially follows (accent foregrounds); the rest is fixed.
