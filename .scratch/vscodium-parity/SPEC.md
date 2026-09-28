# Spec: VSCodium as an opt-in parity twin of the Neovim Config

Status: ready-for-agent

Anchors: ADR 0148 (this decision), ADR 0134 (program `home/` + Config Apply),
ADR 0135/0140 (system-package toolchain, no mason), ADR 0141 (Language
Registry). Glossary: [[VSCodium Config]], [[Editor Coverage Map]],
[[Neovim Config]], [[Language Registry]], [[User Program]].

## Problem Statement

The fleet serves one editor, the hand-rolled [[Neovim Config]]. The operator
also works in VSCodium, but only as a hand-tuned install on one host: the MS
Marketplace patch, ~20 extensions (duplicates, two settings-sync extensions,
tools nvim never had), settings that disagree with nvim (biome fix-all on save,
10s autosave, mauve accent with black overrides, a font family a seeded box
does not have). Nothing about it is reproducible, nothing ties its toolchain to
nvim's, and a fresh install gets no VSCodium at all. When a language is added
to nvim, VSCodium has no way to know.

## Solution

A new opt-in `dev/vscodium` [[User Program]] that seeds VSCodium to cover
everything the Neovim Config does. `vscodium-bin` with extensions from Open VSX
only; the extensions drive the same Host Core system binaries nvim uses
wherever they accept a path; VSCodeVim reproduces the nvim `<leader>` map where
a VSCodium command honestly backs it; look is static Catppuccin Mocha +
sapphire. An [[Editor Coverage Map]] ties VSCodium to the [[Language
Registry]] and a test fails when they diverge. nvim-only features with no
faithful equivalent are listed in ADR 0148, not faked. The operator's existing
host VSCodium is never touched: the program is not stowed by default and is
verified in a VM.

## User Stories

1. As the operator, I want to select a `vscodium` program for a user, so that a
   fresh install ships a ready VSCodium without manual setup.
2. As the operator, I want VSCodium to be opt-in (not in User Core), so that
   nvim stays the one default editor and bare users stay bare.
3. As the operator, I want VSCodium installed from `vscodium-bin`, so that it
   matches the build I already run.
4. As the operator, I want extensions pulled from Open VSX only, so that the
   install does not depend on the MS Marketplace or its licence terms.
5. As the operator, I want the extension list kept as a data file in the
   program, so that adding or removing an extension is a one-line change.
6. As the operator, I want extensions listed by bare ID (unpinned), so that
   installs get current builds and never chase dropped platform versions.
7. As the operator, I want the install to only add extensions, never remove
   them, so that a user's own extensions survive a re-run.
8. As the operator, I want extensions installed per owning user, so that each
   user of the program gets them in their own profile.
9. As the operator, I want settings and keybindings placed by the Config Apply
   pass for the user and `/etc/skel`, so that VSCodium config follows the
   same decoupled model as every other program (and `config_exclude` works).
10. As the operator, I want `./stow-configs.sh` with no arguments to skip
    vscodium, so that running it on a host with its own VSCodium never adopts
    or overwrites that config.
11. As the operator, I want `./stow-configs.sh vscodium` to still stow it, so
    that I can opt a host in deliberately.
12. As a developer, I want Lua to use lua-language-server and stylua from
    `/usr/bin`, so that VSCodium and nvim agree on Lua.
13. As a developer, I want Python to use ruff (lint + format) from `/usr/bin`
    and basedpyright for types, so that Python behaves as in nvim.
14. As a developer, I want TS/JS/JSX/TSX/JSON/CSS formatted by biome from
    `/usr/bin`, so that formatting matches nvim byte for byte.
15. As a developer, I want biome to lint only when a `biome.json` exists, so
    that unconfigured projects are not flooded with diagnostics (as in nvim).
16. As a developer, I want HTML/Svelte/Vue/YAML/Markdown formatted by the
    system prettier, so that those files match nvim's formatting.
17. As a developer, I want Svelte and Vue language servers driven from the
    system packages, so that versions match nvim's.
18. As a developer, I want Go via the system gopls and dlv, so that no
    `go install` of tools happens behind my back.
19. As a developer, I want Rust via the system rust-analyzer and rustfmt, so
    that the server matches nvim's.
20. As a developer, I want Zig via the system zig and zls, so that no managed
    download happens.
21. As a developer, I want C/C++ via the system clangd, so that it matches nvim.
22. As a developer, I want Nix via the system nixd and PHP via the system
    phpactor, so that those servers match nvim's.
23. As a developer, I want bash, YAML, Tailwind, emmet, eslint, JSON, CSS and
    HTML language support present, so that every nvim server has a VSCodium
    counterpart.
24. As a developer, I want `.http`/`.rest` files runnable (REST Client), so
    that my kulala request files work in both editors.
25. As a developer, I want format on save with no fix-all/organize-imports on
    save and no autosave, so that saving behaves as in nvim.
26. As a developer, I want `<leader>co` to organize imports, so that I trigger
    it deliberately, as in nvim.
27. As a developer, I want to debug Python, Go, Rust, C/C++ and JS/TS from
    VSCodium, so that every nvim dap target is covered.
28. As a developer, I want the debug keys (`<leader>db/dB/dc/di/do/dO/dr/dl/
    dt/du`) to act as in nvim, so that muscle memory carries over.
29. As a vim user, I want VSCodeVim with Space leader, `jj` escape, relative
    line numbers and the system clipboard, so that editing feels like nvim.
30. As a vim user, I want `s`/`S` to jump (sneak) like flash, so that motion
    keys match nvim.
31. As a vim user, I want `<leader><space>` to open the smart file picker, so
    that it is not captured by an easymotion prefix.
32. As a vim user, I want `gsa/gsd/gsr` to add/delete/replace surroundings, so
    that surround keys match nvim (fallback `ys/ds/cs` if the remap fails).
33. As a vim user, I want `<leader>ff/fg/fb/fr` (files/grep/buffers/recent),
    so that finding matches nvim.
34. As a vim user, I want `<leader>ss/sS/sc/sk` (symbols/workspace symbols/
    commands/keymaps), so that search matches nvim.
35. As a vim user, I want `<leader>sr` to open search-and-replace, so that
    grug-far's key still works.
36. As a vim user, I want `grn/gra/grr/gri/grd` and `K` for LSP actions, so
    that LSP keys match nvim.
37. As a vim user, I want `]d`/`[d`, `]h`/`[h`, `]t`/`[t` to jump diagnostics,
    hunks and TODOs, so that navigation matches nvim.
38. As a vim user, I want `<leader>xx/xX/xt` to open the Problems/TODO views,
    so that trouble's keys still work.
39. As a vim user, I want `<leader>gg` to open lazygit in the terminal and
    `<leader>gd/gh/gt` for diff/history/blame, so that git keys match nvim.
40. As a vim user, I want `-` to reveal the current file in the explorer and
    `<leader>e` to toggle the explorer, so that oil/explorer keys land
    somewhere sensible.
41. As a vim user, I want `<Tab>`/`<S-Tab>` to cycle editors and `<leader>bd`
    to close one, so that buffer keys match nvim.
42. As a vim user, I want `<C-h/j/k/l>` to move between editor groups and
    `<C-/>` to toggle the terminal, so that window keys match nvim.
43. As a vim user, I want `<leader>w`/`<leader>q` to save/close, so that the
    basics match nvim.
44. As a vim user, I want `<leader>uh` to toggle inlay hints, so that the UI
    toggle matches nvim.
45. As a vim user, I want `<leader>R*` REST keys and `<leader>r*` refactor keys
    (extract via code actions), so that those groups match nvim.
46. As a vim user, I want `zR/zM` folding keys, so that folds behave as in nvim.
47. As the operator, I want Catppuccin Mocha with a sapphire accent and no
    black overrides, so that VSCodium matches nvim's default look.
48. As the operator, I want `<leader>uC` to open a theme picker over the same
    five palettes nvim offers, so that switching palettes works in both.
49. As the operator, I want Catppuccin Mocha file icons that stay fixed across
    palettes, so that icons behave like nvim's devicons.
50. As the operator, I want FiraCode Nerd Font 12 with ligatures in editor and
    terminal, so that VSCodium uses the font a seeded box actually has.
51. As the operator, I want the sidebar on the right and no startup editor, so
    that my existing layout preferences carry over.
52. As the operator, I want sticky scroll on, so that treesitter-context's
    behaviour is covered.
53. As the operator, I want spell checking and git-graph available, so that the
    extras I kept from my host carry over.
54. As a maintainer, I want every Language Registry row mapped in the Editor
    Coverage Map (or marked n/a), so that "what covers X in VSCodium" has one
    answer.
55. As a maintainer, I want a test that fails when the Registry and the
    Coverage Map disagree, so that a new nvim language cannot silently skip
    VSCodium.
56. As a maintainer, I want a test that every toolchain path setting points at
    a binary Host Core declares, so that a renamed package is caught.
57. As a maintainer, I want a test that the program never references the MS
    Marketplace, so that the Open VSX rule cannot regress.
58. As a maintainer, I want the bundled/downloaded exceptions and the parity
    gaps listed in one place (ADR 0148), so that nobody "fixes" them blindly.
59. As the operator, I want a VM run proving install, extensions, system
    servers, format on save and the surround remap, so that I trust it before
    using it on a real host.

## Implementation Decisions

- **New `dev/vscodium` User Program** (`kind: user`), shaped like `dev/nvim`:
  metadata file, `install.sh`, single-source `home/`. Header points at ADR
  0148 for the gap list. Not added to User Core.
- **`install.sh`** installs `vscodium-bin` (AUR) and then, as the owning user,
  runs `codium --install-extension <id>` for every ID in the program's
  extension data file (one ID per line, comments allowed). Additive only; no
  uninstall; no seeding of `home/` (Config Apply does that).
- **Extension set** (Open VSX IDs): VSCodeVim; catppuccin theme + icons;
  rose-pine, tokyonight, gruvbox, nord themes (availability checked during the
  ticket); rust-analyzer, golang.go, basedpyright, ms-python.python, debugpy,
  ruff, biome, prettier, stylua, sumneko.lua, clangd, vscode-zig, codelldb,
  svelte, Vue (volar), tailwindcss, redhat yaml, bash-ide, nix-ide, eslint,
  phpactor, REST Client, todo-tree, git-graph, code-spell-checker. js-debug is
  built in.
- **Settings** hold: system binary paths (rust-analyzer server path, go
  alternate tools for gopls/dlv, ruff path, biome LSP bin with
  require-configuration, prettier module path, stylua path, lua-language-server
  executable, clangd path, zig/zls paths, nixd server path, phpactor path,
  svelte/vue server paths); per-language default formatter mirroring the
  Registry's formatter column; format on save on, no code actions on save, no
  autosave; theme, accent, icons, font, sidebar, sticky scroll; VSCodeVim
  options (leader, sneak on, easymotion off, surround on, clipboard, handled
  keys) and leader bindings.
- **Keybindings** split: VSCodeVim leader/normal/visual bindings live in the
  settings; VSCodium-native chords (terminal toggle, group navigation, vim
  toggle) live in the keybindings file.
- **Editor Coverage Map** is a data file in the program: one line per Language
  Registry key → extension ID(s) or `n/a` (with a reason for parser-only rows
  like vimdoc/regex/latex/typst/http where applicable).
- **Stow opt-in**: the pure stow-selection logic gains an opt-in set — programs
  in it are dropped from the no-argument selection but kept when named
  explicitly. vscodium is the first member. Install-time Config Apply is
  unaffected (selection there is by program choice).
- **No Host Core change**: rust and zig come in as dependencies of
  rust-analyzer and zls.
- **Gaps and exceptions** stay authoritative in ADR 0148; the spec does not
  duplicate them.

## Testing Decisions

- Good tests assert committed, externally visible artefacts (program files,
  parsed JSON values, selection output) — not how install.sh is written line
  by line.
- **Program static test** (new bats file, prior art: the nvim, kitty, pi and
  lazygit program tests): program metadata and install.sh shape; install.sh
  does not seed `home/`; settings and keybindings parse as JSON (via the repo's
  JSONC helper); every path setting resolves to a binary a Host Core package
  provides; each Registry formatter has the matching default formatter;
  sapphire accent, the five palettes, catppuccin-mocha icons, FiraCode Nerd
  Font; sneak on, easymotion off; no MS Marketplace reference anywhere in the
  program.
- **Coverage Map test** (same file): Registry keys extracted from the nvim
  language registry with awk (no Lua runtime) equal the Coverage Map keys; each
  non-n/a extension ID appears in the extension list.
- **Stow opt-in** (extend the existing config-apply test of the pure selection
  function): opt-in names are skipped with no args, honoured when named,
  unaffected by `--except`.
- **No-python** guard already covers the new files.
- **VM acceptance** via vm-agent on a profile selecting vscodium: extension
  list matches, servers in use are the `/usr/bin` ones, format on save in a TS
  and a Rust file, the `gs*` surround remap, a themed screenshot. Result
  recorded in the ticket; the surround outcome decides remap vs `ys/ds/cs`.

## Out of Scope

- Touching the operator's host VSCodium (config, extensions, stow).
- Noctalia live follow for VSCodium (possible follow-up).
- MS Marketplace, settings sync, harpoon, undotree, orgmode, which-key menu,
  ErrorLens-style inline diagnostics (see ADR 0148 gaps).
- Swift support.
- Any Host Core package change.
- Making VSCodium a User Core default.

## Further Notes

- Open VSX lags upstream for rest-client, todo-tree and git-graph; accepted
  and recorded in ADR 0148.
- codelldb downloads its adapter from GitHub on the first debug session; the
  VM check should note whether that network step succeeds.
- Vue server path form (dir vs entry file) and whether the phpactor extension
  bundles its own binary are unverified; settle in the relevant ticket.
