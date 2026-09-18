# Spec: Served Neovim config (hand-rolled, Noctalia-aware)

Status: ready-for-agent

Anchors: ADR 0135 (hand-rolled nvim on lazy.nvim; system-package LSP),
ADR 0136 (nvim follows Noctalia via its own base16 template; amends ADR 0132).
Glossary: [[Neovim Config]], [[Neovim Theme Template]], [[Live Theme Bridge]],
[[Pi Theme Template]], [[Kitty Config]], [[ANSI-16 Following]], [[User Program]].
Prototype (parity target): `.scratch/nvim-prototype/prototype.html`.

## Problem Statement

The repo carries two Neovim configs — a LazyVim distro at `.config/nvim` and an
older hand-rolled tree at `.config/nvim.bak` — and neither is the deliberate,
single served editor the rest of the fleet userland has. The operator wants one
served config: a modern editor already equipped for their full language set,
`:checkhealth`-clean on a fresh box, and cohesive with the rest of the desktop —
optionally following the live Noctalia palette, but by default sitting on a
fixed, curated Catppuccin Mocha Sapphire look. Today nvim is the lone app
excluded from Noctalia theming (ADR 0132), which breaks that cohesion.

## Solution

Serve one **hand-rolled Lua Neovim config on `lazy.nvim`** (not LazyVim, not
`vim.pack` yet), targeting **stable Neovim 0.12.x**. Deliver it like
[[Kitty Config]]: a `dev/nvim` [[User Program]] owns the editor's extra
toolchain as **system packages** (no `mason`), and the config tree is seeded +
stow-ready at the repo root. Ship a curated static default — Catppuccin Mocha
with a **sapphire accent** (`#74c7ec`), switchable among the five Noctalia
builtin palettes — and a `follow_noctalia` toggle (**default `false`**) that,
when on, makes nvim follow the live palette through a new [[Neovim Theme
Template]] (base16 from Noctalia's 16 terminal colors, self-reloading via
`fs_event`). The arch-combined VM is screenshotted against the prototype and
gated on a clean `:checkhealth`.

## User Stories

1. As the operator, I want a single served Neovim config, so that there is one
   editor of record instead of a distro and a `.bak` tree.
2. As the operator, I want the config hand-rolled on lazy.nvim, so that I keep
   full control and no opaque distro layer, consistent with the repo ethos.
3. As the operator, I want to target stable Neovim 0.12.x, so that it matches
   what Arch ships and the VM stays reproducible.
4. As the operator, I want the config installed as a `dev/nvim` User Program,
   so that its toolchain is declarative and reproducible like every other
   program.
5. As the operator, I want LSP servers, formatters and linters installed as
   system packages (repo, AUR only for gaps), so that nothing is duplicated into
   nvim's data dir and the installer stays the single source of truth.
6. As the operator, I want no `mason`, so that package management doesn't fork
   away from the declarative `language-servers` convention.
7. As the operator, I want first-class LSP for html, css, js, ts, react,
   svelte, solid, vue, php, json, yaml, python, lua, rust, zig, nix, go, c, c++,
   so that every language I use is equipped out of the box.
8. As the operator, I want solid to ride the TypeScript server, so that I don't
   wait on a dedicated server that doesn't exist.
9. As the operator, I want Swift support best-effort/optional, so that a missing
   AUR sourcekit-lsp never breaks health or the install.
10. As the operator, I want completion via blink.cmp, so that completion is
    fast and modern.
11. As the operator, I want treesitter highlighting, folding and text objects,
    so that editing is structural.
12. As the operator, I want formatting via conform and linting via nvim-lint,
    so that format-on-save and diagnostics follow project config (biome,
    prettier, stylua, ruff, and native fmt tools).
13. As the operator, I want git integration via gitsigns + fugitive, so that I
    see signs/blame inline and run raw git.
14. As the operator, I want two explorers — oil (buffer-as-directory) and
    neo-tree (sidebar) — so that I can pick per task.
15. As the operator, I want a snacks-based picker, dashboard and notifier, so
    that fuzzy-find, the start screen and toasts come from one cohesive stack.
16. As the operator, I want lualine + bufferline, so that the statusline and
    buffer tabs are legible and accent-aware.
17. As the operator, I want harpoon, which-key, mini.ai, mini.pairs,
    render-markdown, todo-comments, undotree and nvim-emmet, so that the editing
    workflow I already use is present.
18. As the operator, I want no noice, so that the config has fewer breakage-
    prone moving parts and stays health-clean.
19. As the operator, I want unused language providers (perl/ruby/node) explicitly
    disabled, so that `:checkhealth` shows no spurious warnings.
20. As the operator, I want the default theme to be Catppuccin Mocha with a
    sapphire accent, so that nvim matches the fleet default out of the box.
21. As the operator, I want to switch among the five Noctalia builtin palettes
    (rose-pine, catppuccin, tokyonight, gruvbox, nord) from within nvim, so that
    I can change the static look without editing files by hand.
22. As the operator, I want a `follow_noctalia` toggle defaulting to `false`, so
    that a fresh install is static and predictable unless I opt in.
23. As the operator, when I set `follow_noctalia = true`, I want nvim to follow
    the live Noctalia palette, so that the editor tracks a mid-session theme
    change like kitty and pi do.
24. As the operator, I want the follow path to reuse Noctalia's 16 terminal
    colors rendered into a base16 nvim theme, so that highlighting stays
    truecolor and full-coverage rather than collapsing to 16 ANSI slots.
25. As the operator, I want the generated nvim theme file to be seed-only and
    gitignored (only the template input stowed), so that it matches the
    kitty/pi/zsh template discipline (ADR 0104).
26. As the operator, I want the follow behavior isolated to compositor sessions,
    so that niri/Hyprland follow live while KDE stays fixed on Mocha Sapphire.
27. As the operator, I want the generated theme seeded with Catppuccin Mocha
    Sapphire, so that first boot resolves offline with no network.
28. As the operator, I want the swap from the old configs deferred until the
    fresh one passes on the VM, so that the served path is never broken.
29. As the operator, I want `:checkhealth` to show zero ERROR with every
    in-scope LSP on PATH, so that a fresh box is fully equipped on first run.
30. As the operator, I want the arch-combined VM output to match the prototype,
    so that the shipped look is the one I approved.

## Implementation Decisions

- **Base.** Hand-rolled Lua config on `lazy.nvim`; not the LazyVim distro, not
  `vim.pack` (revisited when 0.13 is stable). Target stable 0.12.x. Built fresh
  — `.config/nvim.bak` is reference only, not a base (ADR 0135).
- **Delivery.** A new `dev/nvim` [[User Program]] under
  `.installer/programs/dev/nvim/`, authored per `PROGRAM_SPEC.md`, kind=user.
  The config tree is single-source under the program's `home/.config/nvim/`
  (ADR 0134) and seeded + stow-ready; the Runner's Config Apply pass places it,
  so `install.sh` installs packages only. `neovim`/`neovide` remain in Host
  Core; the program owns the *extra* toolchain.
- **Toolchain as system packages** (no `mason`), repo where possible, AUR for
  gaps, arch-wiki-grounded:
  - Already present (Host Core `language-servers`/`dev`): rust-analyzer, gopls,
    zls, clang, typescript-language-server, yaml-language-server,
    bash-language-server, vscode-langservers-extracted, biome.
  - Add: lua-language-server, basedpyright, ruff, nil, phpactor,
    svelte-language-server, vue-language-server (Volar),
    tailwindcss-language-server, emmet-language-server, stylua, prettier.
  - Swift/sourcekit-lsp: AUR, best-effort, guarded — never blocks health.
- **LSP wiring.** Native `vim.lsp.config`/`vim.lsp.enable` (0.12) fronted by
  nvim-lspconfig defaults, with lazydev + fidget. solid uses the ts server.
- **Format/lint.** conform: biome (js/ts/jsx/tsx/json/css), prettier
  (html/svelte/vue/yaml/md), stylua (lua), ruff (py), native rustfmt/gofmt/
  `zig fmt`. nvim-lint for biome/ruff diagnostics where the LSP doesn't cover.
- **Roster (final).** blink.cmp, nvim-treesitter, nvim-lspconfig(+lazydev,
  fidget), conform, nvim-lint, gitsigns, fugitive, oil, neo-tree, snacks
  (picker/dashboard/notifier), lualine, bufferline, harpoon, which-key,
  mini.ai, mini.pairs, nvim-ufo, render-markdown, todo-comments, undotree,
  nvim-emmet. No noice. Unused providers (perl/ruby/node) disabled in options.
- **Theme model ([[Neovim Theme Template]], ADR 0136).** A `follow_noctalia`
  Lua setting (default `false`) read at startup:
  - `false` → static Catppuccin Mocha, accent overridden to sapphire `#74c7ec`;
    a picker (snacks) switches among the five builtin palettes and persists the
    choice (as the current config persists a chosen colorscheme).
  - `true` → load the generated base16 theme and `fs_event`-watch it, re-applying
    highlights on write (mid-session), so the [[Live Theme Bridge]] is untouched.
- **Bridge seam.** A new `[theme.templates.user.nvim]` in
  `.config/noctalia/config.toml` maps Noctalia's 16 terminal colors (+ `primary`
  as accent) into a nvim-native base16 file; template input is stowed, output is
  seed-only/gitignored, seeded with Catppuccin Mocha Sapphire (ADR 0109),
  rewritten only in compositor sessions (niri/Hyprland follow, KDE fixed).
- **Amendment.** ADR 0132's "Neovim is excluded" carve-out is amended; the
  [[ANSI-16 Following]] glossary entry already points at the new template.
- **Cutover (disposition (c)).** Build + verify in `.scratch/` (or `nvim.new`)
  against the prototype and VM, then atomically swap into the served
  `.config/nvim` and delete both the LazyVim tree and `.config/nvim.bak`.

## Testing Decisions

A good test asserts external behavior, not implementation detail: the committed
program/template *shape* and the *observable editor state*, never a specific
plugin's internals. Two seams (confirmed with the operator):

- **Seam A — static installer/config bats (reused).** New
  `.installer/tests/config/nvim-program.bats`, cloned from
  `kitty-program.bats`/`pi-agent.bats`: `dev/nvim` `config.jsonc` is kind=user;
  `install.sh` has the mandated `set -Eeuo pipefail` + trap shape, owns the
  extra toolchain packages, seeds the generated theme into
  `$HOME`/`/etc/skel`/`/root`, and runs no `systemctl start`; `home/.config/nvim`
  is the single source; the generated theme output is gitignored. Extend
  `noctalia-stow.bats` to assert `[theme.templates.user.nvim]` registration, the
  stowed template input, and the Mocha-Sapphire seed default — mirroring the
  kitty/pi/zsh template assertions. Prior art: `.installer/tests/config/*.bats`.
- **Seam B — headless-nvim probe (new, highest point).** One
  `nvim --headless -l <probe>` entrypoint booting the real served config:
  - portable/CI: `follow_noctalia == false`, active colorscheme is Catppuccin
    Mocha, the accent highlight resolves to sapphire `#74c7ec`, and re-writing
    the generated theme file re-applies it;
  - VM harness verify-block (arch-combined): `:checkhealth` reports zero ERROR
    and every in-scope LSP resolves on `PATH`. Prior art: the VM harness /
    `flow-test.sh` verify-block and `niri-adapter.bats` seed-key assertions.

No per-plugin tests and no per-language test; those are implementation detail.
Benign `:checkhealth` WARNs are allowed (optional Swift, disabled providers).

## Out of Scope

- Migrating to `vim.pack` (deferred until Neovim 0.13 is stable).
- Making KDE/Plasma sessions follow the live palette (compositor-only, by
  design — KDE stays fixed on Mocha Sapphire).
- GUI clients (neovide theming beyond what the terminal config yields).
- A full 53-role M3 colorscheme map (base16 from the 16 terminal colors
  suffices; a richer map is a later refinement, not this spec).
- Persisting the `follow_noctalia` toggle across machines beyond the normal
  seed/stow of the config.
- Any change to how the other ANSI-16-following CLIs are themed.

## Further Notes

- Neovim is treated as a first-class heavy app (like pi), which is why it gets
  its own template rather than deferring to the terminal's 16 ANSI slots: with
  `termguicolors` on, ANSI-16 following would collapse treesitter/LSP
  highlighting to 16 colors.
- The prototype (`.scratch/nvim-prototype/prototype.html`) is the visual parity
  target for the VM screenshots; it encodes the 13 screens and the exact
  Mocha-Sapphire palette roles. Operator has approved it.
- Reference-only prior config: `.config/nvim.bak` (blink.cmp, native treesitter,
  conform, nvim-lint, mason-based LSP) — mined for plugin choices, then deleted
  at cutover along with the LazyVim tree.
