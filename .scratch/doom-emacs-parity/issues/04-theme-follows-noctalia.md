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

**Status:** ready-for-agent

- [ ] Follow on → Noctalia theme if its file exists, else Catppuccin; follow
      off → picked static palette
- [ ] `SPC u C` / `SPC u N` bound; the five palettes installed
- [ ] `server-start` guarded on no running server; no `emacs.service`
- [ ] Rendered theme file git-ignored and excluded from stow
- [ ] Static bats: palettes, follow logic, server guard present
- [ ] VM: Emacs opens Noctalia-themed; a palette change reaches the open
      Emacs; KDE-like no-template fallback shows Catppuccin; in Comments

## Comments
