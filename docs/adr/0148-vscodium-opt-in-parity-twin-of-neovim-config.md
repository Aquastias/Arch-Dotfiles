# ADR 0148: VSCodium as an opt-in parity twin of the Neovim Config

## Status
Accepted — implemented. Adds the `dev/vscodium` [[User Program]]
([[VSCodium Config]]) and the [[Editor Coverage Map]] test. VM-verified on a
fresh `arch-combined` install (niri): all extensions, system servers in use,
format on save (biome, rustfmt), `gs*` surround, leader keys, a debugpy
breakpoint, sapphire accent. Leans on ADR 0134 (program `home/` + Config
Apply), ADR 0135/0140 (system-package toolchain, no mason) and ADR 0141
([[Language Registry]]).

## Context
The fleet serves exactly one editor, the hand-rolled [[Neovim Config]]. The
operator also uses VSCodium, but only as a hand-tuned host install
(`vscodium-bin` + the `vscodium-marketplace` patch, ~20 extensions incl.
duplicates and two settings-sync extensions) that the installer knows nothing
about. The goal is a seeded VSCodium that covers everything the nvim config
does, without becoming a second, drifting source of truth for the toolchain.

## Decision
- **Opt-in User Program**, not User Core: nvim stays the one default editor.
  `vscodium-bin` from AUR; extensions from **Open VSX only**. The MS
  Marketplace patch is rejected — its terms limit it to MS products, and every
  needed extension is on Open VSX.
- **Parity = feature parity + key parity.** Same languages, formatters,
  linters and debuggers as nvim; VSCodeVim reproduces the nvim `<leader>` map
  wherever a VSCodium command honestly backs it. No faked equivalents — gaps
  are listed below instead.
- **Same toolchain.** Extensions are pointed at the Host Core system binaries
  (`/usr/bin/…`) wherever they expose a path setting: rust-analyzer, gopls/dlv,
  ruff, biome, stylua, lua-language-server, clangd, zig/zls, nixd, phpactor,
  svelte, vue, prettier. Bundled servers are the listed exception only.
- **Registry-linked coverage.** An [[Editor Coverage Map]] maps every
  [[Language Registry]] row to its extension(s) or an explicit *n/a*; a test
  fails when its keys differ from the Registry's. Swift is not a Registry row
  (best-effort in nvim) and gets no extension.
- **Delivery.** `settings.json`/`keybindings.json` in the program's `home/`
  (Config Apply: owning user + `/etc/skel`, not `/root`); `install.sh`
  installs a data-file list of **unpinned** extension IDs per owning user and
  never uninstalls. `stow-configs.sh` does **not** stow vscodium by default —
  only when named — so an operator host's own VSCodium is never adopted into
  or overwritten by the repo.
- **Behaviour follows nvim over the old host config:** format on save only (no
  biome fix-all/organize-imports on save, no autosave — autosave-after-delay
  skips format-on-save); organize imports on `<leader>co`. Look: static
  Catppuccin Mocha + sapphire accent, no black overrides, `catppuccin-mocha`
  icons (fixed across palettes, like devicons), `FiraCode Nerd Font` 12 with
  ligatures (the font `lib/config/fonts.sh` seeds). Kept host preferences:
  sidebar right, `jj` escape, `<C-a/f/p>` passed through, system clipboard.
- **Server paths** (settled in ticket 03): Vue's `vue.server.path` takes the
  `@vue/language-server` module dir; svelte's `ls-path` takes Arch's
  `svelteserver` (a symlink to the package's `bin/server.js`); phpactor's
  `phpactor.path` takes the binary the `dev/nvim` program installs.
- **Motions/keys:** `vim.sneak` on `s`/`S` stands in for flash; easymotion is
  off (its `<leader><leader>` prefix collides with nvim's smart picker).
  `gs*` is remapped onto VSCodeVim surround (`<plugys>`/`<plugds>`/
  `<plugcs>`), VM-verified (`gsa`, `gsd`, `gsr`). `<leader>uC` opens the
  theme picker over five installed palettes (catppuccin, rose-pine,
  tokyonight, gruvbox, nord). `-` reveals the file in the explorer (oil
  stand-in); `<leader>gg` runs `lazygit` in the integrated terminal.

### Bundled / downloaded exceptions
No system-path setting exists, so these use the extension's own copy:
tailwindcss, yaml, bash-ide server, basedpyright (resolves the Python
package, not the PATH binary), debugpy, js-debug (built into VSCodium), and
codelldb (the extension downloads its platform adapter from GitHub the first
time VSCodium activates it).
The TypeScript/JavaScript, JSON, CSS, HTML and emmet language features are
VSCodium built-ins — the same servers nvim gets from
`typescript-language-server`/`vscode-langservers-extracted`, but VSCodium's
own copies.

### Behaviour differences
biome: nvim lints with biome only when a `biome.json` exists; the biome
extension has no lint-only switch (`biome.requireConfiguration` disables
formatting too), so VSCodium formats everywhere and lints with biome's
recommended rules even without a config.
Debug start: nvim-dap's `<leader>dc` both starts and continues; VSCodium's
`workbench.action.debug.continue` only continues a paused session, so
`<leader>dl` (nvim: run last) starts the selected launch config and `dc`
continues. Rust/C launch configs come from codelldb (e.g. from `Cargo.toml`)
instead of nvim's executable-path prompt.

### Parity gaps (nvim-only)
harpoon (only a <2k-download Open VSX port), undotree (none on Open VSX),
orgmode (agenda-driven; no faithful extension), which-key menu (plain leader
bindings instead; the whichkey extension is a second keymap source),
Noctalia follow / `<leader>uN` (static theme; possible follow-up), inline
diagnostic virtual text (hover + `]d`/`[d` + Problems instead), oil's
buffer-editing of directories. Unmapped nvim keys (no VSCodium command backs
them): `<leader>uh` (no inlay-hint toggle command), `]t`/`[t` (todo-tree has
no next/prev), `<leader>xX/xq/xl/xs`, `<leader>fh`, `<leader>Ra/Rn/Rp/Ri`,
`<leader>rw`, `cn`/`cN`, `<leader>cx`, `<leader><cr>`, mini.ai's treesitter
`af`/`ac`/`ao` textobjects. Folds (`zR/zM/zr/zm`) are VSCodeVim built-ins.

### Kept despite Open VSX lag
rest-client (kulala stand-in; same `.http` format — upstream active but last
Open VSX publish 2022), todo-tree (2022) and git-graph (2021; upstream idle).
All still work; a VSCodium API break would go unfixed. Also kept:
code-spell-checker. Dropped from the host set: settings-sync extensions,
thunder-client, docker, githistory, eslint-only duplicates.

## Considered Options
- **MS Marketplace patch** (host status quo) — licensing, rejected.
- **Extensions' bundled servers everywhere** — simpler, but a second toolchain
  drifting from nvim's; rejected except where unavoidable.
- **VSpaceCode whichkey** for leader discovery — stale (2024) and a second
  keymap model; rejected for v1.

## Consequences
- A new Registry row fails the coverage test until VSCodium covers it (or
  marks it *n/a*) — intended friction.
- codelldb needs network the first time VSCodium starts (adapter download).
- VSCodium's workspace trust stays on (upstream default): a first-opened
  folder is in Restricted Mode, with most extensions off, until trusted.
  nvim has no such gate; the prompt is kept as a deliberate safety net.
- Toolchain needs no Host Core addition: `rust-analyzer → rust-src → rust`
  (rustfmt) and `zls → zig` (zig fmt) already pull both toolchains in.
- Host Core **drops** `vscodium-bin` and `vscodium-marketplace` from
  `packages.aur.misc` (found during implementation): every host used to get
  VSCodium plus the Marketplace patch, which would have pointed
  `--install-extension` at the MS Marketplace and made VSCodium fleet-wide.
  The program now owns the package; a host gets VSCodium only by opting in.
