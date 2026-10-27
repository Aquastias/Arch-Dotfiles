# 04: Theme follows Noctalia

**What to build:** Emacs follows the live Noctalia palette like nvim (ADR
0160). Noctalia's built-in `emacs` template (already enabled fleet-wide)
renders a theme into the Doom config dir; Emacs loads it when present, else
static Catppuccin Mocha + sapphire. `SPC u C` picks among nvim's five
palettes, `SPC u N` toggles follow. Emacs starts a server when none runs, so
Noctalia's `emacsclient` apply hook reaches the open Emacs; no login daemon.
The rendered theme file is seed-only (ADR 0104): never tracked, never
stowed.

**Blocked by:** 01 (Tracer).

**Status:** done

- [x] Follow on → Noctalia theme if its file exists, else Catppuccin; follow
      off → picked static palette
- [x] `SPC u C` / `SPC u N` bound; the five palettes installed
- [x] `server-start` guarded on no running server; no `emacs.service`
- [x] Rendered theme file git-ignored and excluded from stow
- [x] Static bats: palettes, follow logic, server guard present
- [x] VM: Emacs opens Noctalia-themed; a palette change reaches the open
      Emacs; KDE-like no-template fallback shows Catppuccin; in Comments

## Comments

- nvim's follow defaults **off** (`options.lua`); operator chose to match:
  Emacs starts on the persisted static palette (Catppuccin default) and
  `SPC u N` turns follow on. ADR 0160's "follows Noctalia" wording needs
  this correction at close-out.
- Noctalia's apply hook runs `(load-theme 'noctalia t)` on every palette
  change; a `load-theme` advice ignores it while follow is off.
- rose-pine has no maintained Emacs theme (not on MELPA or in doom-themes):
  four of nvim's five palettes — a gap for the ADR.
- Sapphire overlays Catppuccin only (`custom-theme-set-faces!`), so a
  followed Noctalia palette keeps its own accent, as in nvim.

- VM (arch-niri, niri session): static Catppuccin with sapphire (fixed:
  evil cached the cursor color before the overlay); SPC u N → noctalia;
  `noctalia msg color-scheme-set builtin Nord` repainted the open Emacs live
  (#2e3440); with follow off a palette change left Catppuccin; SPC u C pick
  persisted across restart. Palette restored afterwards.
