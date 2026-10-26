# ADR 0160: Doom Emacs as an opt-in parity twin of the Neovim Config

## Status
Accepted — design only; not yet implemented. Adds the `dev/emacs`
[[User Program]] ([[Emacs Config]]) and a second [[Editor Coverage Map]].
Holds Emacs to the parity contract of [ADR 0148] (VSCodium) and leans on
[ADR 0134] (program `home/` + Config Apply), [ADR 0135]/[0140]
(system-package toolchain) and [ADR 0141] ([[Language Registry]]).

## Context
The operator wants Emacs on desktop and laptop, mirroring the [[Neovim
Config]] the way VSCodium does — and specifically the **Doom Emacs** distro.
[ADR 0135] rejected a distro (LazyVim) for nvim in favour of a hand-rolled
config, so using one here needs a reason. Doom is not packaged (no AUR
package; upstream installs by git clone + `doom install`) and fetches ~200
packages from the network on `doom sync`. Noctalia already renders an Emacs
theme: its built-in `emacs` template (on in `.config/noctalia/config.toml`)
writes `themes/noctalia-theme.el` into the first existing dir of
`~/.config/doom`, `~/.config/emacs`, `~/.emacs.d`, and applies it live via
`emacsclient`.

## Decision
- **Opt-in User Program**, like VSCodium: listed in aquastias's profile, so it
  lands on desktop, laptop and the VM fixtures carrying that user. nvim stays
  the one default editor; `stow-configs.sh` stows emacs only when named.
- **Packages.** `emacs-wayland` (pgtk) from `extra` — the fleet desktops are
  all Wayland. Doom core (`doomemacs/core`) is a git clone into
  `~/.config/emacs`, **pinned** to the commit in the program's `doom-ref` data
  file — which also pins its modules (`doomemacs/modules`, a submodule
  gitlink); moving it is a deliberate one-line commit. Extra packages carry
  `:pin`s like Doom's own. The user config (`~/.config/doom`) is in the
  program's `home/` (Config Apply).
- **Sync runs in a Post-Config Hook**, at install time but after Config
  Apply: Doom bakes its config dir's absolute path into the profile it
  generates, and the Runner places config only after every `install.sh`. A
  program may now ship `post-config.sh`, run as its user once its `home/` is
  placed (amends [ADR 0134]); `dev/emacs`'s runs `doom install` (unattended,
  no env file). A failed sync warns rather than fails (an upstream blip is a
  gap, not a broken install).
- **Doom is acceptable here**, not for nvim, because the twin is opt-in and
  never the served default: distro opacity costs only its opt-in users.
- **Parity = [ADR 0148]'s contract.** Feature + key parity, gaps listed not
  faked, same system toolchain, a Registry-linked coverage map
  (`dev/emacs/coverage.txt` → Doom module/package or *n/a*) whose test fails
  on drift.
- **Toolchain.** LSP via Doom's `:tools lsp +eglot` (servers from PATH only;
  lsp-mode's server auto-install would be a second toolchain). Format on save
  via `:editor format +onsave` (apheleia) set to conform's per-language
  formatters; no fix-all on save. Debugging via **dape** (`packages.el`) on
  nvim-dap's system adapters (debugpy, `codelldb`, dlv, `js-debug-dap`) —
  Doom's `:tools debugger` is dap-mode, which needs lsp-mode. Linting via
  `:checkers syntax +flymake`.
- **Keys: nvim wins.** Doom's evil + `SPC` leader carry the nvim map; where
  Doom's own binding collides, the nvim binding replaces it and Doom keeps
  every free key. So `SPC g g` is lazygit (vterm) and magit moves to
  `SPC g m`; `s` is avy (`avy-goto-char-timer`, flash stand-in) with
  evil-snipe off; `-` is `dired-jump` (wdired gives oil's buffer editing);
  `SPC e` toggles treemacs (right side).
- **Gaps VSCodium had, closed here:** harpoon (`harpoon.el`: `SPC a`, `C-e`,
  `SPC 1..N`), undotree (`:emacs undo +tree` on `SPC U`), which-key (Doom
  built-in), orgmode (native org), inlay-hint toggle (`SPC u h`). REST uses
  `restclient` on `SPC R s`/`SPC R c` — a **loose match**: its format is
  close to, not identical with, rest.nvim's `.http`.
- **Look follows Noctalia, like nvim.** Load `noctalia` from the template's
  theme file when present, else static Catppuccin Mocha + sapphire
  (`catppuccin-theme`); `SPC u C` picks among nvim's five palettes, `SPC u N`
  toggles follow. `config.el` calls `server-start` when no server runs, so
  Noctalia's `emacsclient` apply hook reaches the open Emacs — no login
  daemon. `FiraCode Nerd Font` 12, nerd-icons.
- **Org** shares nvim's files: `org-directory` `~/orgfiles`, agenda
  `~/orgfiles/**`, default notes `~/orgfiles/refile.org`.
- **Audit.** `audit.sh` checks `doom doctor` is clean, the pinned commit is
  checked out, and `emacs --batch` bind probes from `audit-binds.jsonc`.

## Considered Options
- **Hand-rolled `init.el`** (use-package + eglot, as [ADR 0135] did for nvim)
  — the repo's usual ethos, but the operator wants Doom; acceptable only
  because the twin is opt-in.
- **`host_programs` on desktop/laptop** — system-wide, not user-owned; breaks
  the per-user Config Apply that VSCodium already uses.
- **Keep Doom's map, document nvim differences** — defeats key parity.
- **lsp-mode + dap-mode** (Doom defaults) — downloads its own servers.
- **Unpinned Doom / sync on first launch** — Doom master breaks more often
  than Open VSX extensions; first launch would stall on ~200 fetches.
- **`emacs.service` user daemon** — would start Emacs at every login just for
  theme follow; `server-start` inside the open Emacs is enough.

## Consequences
- A new Registry row fails the Emacs coverage test until covered or *n/a*.
- `doom sync` needs network at install time; a failed sync leaves Emacs
  installed but Doom unsynced until `doom sync` is re-run.
- `/etc/skel` gets `~/.config/doom` but not the Doom core clone: a user
  created later runs `doom install` themselves (VSCodium's per-owning-user
  extensions have the same shape).
- Because `~/.config/doom` exists, Noctalia's template targets it, so the
  theme file lands inside the program's `home/` tree on disk; it must stay
  untracked/unstowed (seed-only, as with other Noctalia outputs, [ADR 0104]).
- Doom's vterm module compiles a native module (needs `cmake`, `libvterm`);
  the exact toolchain additions are grounded against the Arch Wiki at
  implementation.

<!-- ADR links: generated by readability.sh --fix-adr-links -->
[0140]: 0140-neovim-debugging-nvim-dap-system-adapters.md
[ADR 0104]: 0104-dual-session-app-theming-isolation.md
[ADR 0134]: 0134-per-program-config-home-decoupled-from-install.md
[ADR 0135]: 0135-hand-rolled-neovim-on-lazynvim-system-lsp.md
[ADR 0141]: 0141-neovim-language-registry-drives-toolchain.md
[ADR 0148]: 0148-vscodium-opt-in-parity-twin-of-neovim-config.md
