# Neovim IDE Expansion

Status: ready-for-agent
Labels: ready-for-agent
ADRs: 0135, 0136, 0140, 0141

## Problem Statement

I use the fleet's shipped [[Neovim Config]] as my daily editor across a wide
language set (web + systems). It is already a clean, fast, hand-rolled
lazy.nvim config, but as an *IDE* it has real gaps: there is no debugger at
all, no project-wide find-and-replace, no in-editor API testing, no
refactoring commands, and no sticky-scroll/surround/auto-tag/jump-motion
ergonomics I relied on in VS Code and WebStorm. Adding a language today means
editing several plugin specs by hand and keeping them in sync. I also want to
be sure every plugin I adopt has real community behind it — I don't want to
build on a single-maintainer plugin that gets archived next month. And it must
stay *performant*: fewer plugins doing most of the job, everything lazy-loaded.

## Solution

Expand the served [[Neovim Config]] into a full IDE without sacrificing
startup performance, by: (1) adding a small set of vetted, actively-maintained
plugins — each lazy-loaded to ~zero startup cost and each filling a distinct
gap with no overlap; (2) closing the remaining VS Code / WebStorm feature gaps
with **native or existing-plugin config** rather than new dependencies
(multi-cursor, symbols, command palette, incremental selection, inlay hints,
indent guides); (3) driving the whole per-language toolchain from a single
**[[Language Registry]]** so adding a language is one table row (ADR 0141);
(4) adding a debugger via **nvim-dap** with adapters installed as **system
packages**, not mason (ADR 0140); and (5) dropping the abandoned `nvim-emmet`
in favour of the Emmet LSP already installed. The theme story is unchanged:
`follow_noctalia` stays default-off, static default remains Catppuccin Mocha
Sapphire, and the five-builtin 1:1 mapping is untouched (ADR 0136).

## User Stories

1. As the fleet editor user, I want a debugger inside Neovim, so that I can set
   breakpoints and step through code without leaving the editor.
2. As a Python developer, I want debugpy wired for debugging, so that I can
   debug Python programs and tests.
3. As a Go developer, I want delve wired for debugging, so that I can step
   through Go code.
4. As a Rust / C / C++ developer, I want codelldb wired, so that one adapter
   debugs all three native languages.
5. As a JS/TS developer, I want js-debug wired, so that I can debug Node and
   browser-adjacent JavaScript/TypeScript.
6. As the fleet maintainer, I want debug adapters installed as system packages
   (not mason), so that debugging stays reproducible and consistent with how
   LSP servers, formatters and linters are already installed (ADR 0135/0140).
7. As a user, I want a visible debug UI (scopes, breakpoints, stacks, repl),
   so that I can inspect program state while stepping.
8. As a user, I want debugging keybinds under a single `<leader>d` group, so
   that all debug actions are discoverable in one place.
9. As a user, I want the debugger to lazy-load, so that it costs nothing at
   startup when I'm not debugging.
10. As someone resolving merge conflicts, I want a side-by-side conflict
    resolver, so that multi-file merges are manageable.
11. As someone reviewing history, I want a navigable file/branch history diff
    view with real syntax highlighting, so that I can read a file's evolution
    better than a terminal pager allows.
12. As a user, I want lazygit to remain my daily git driver, so that diffview
    complements rather than replaces my existing git flow.
13. As a user, I want a project-wide find-and-replace with live match preview,
    so that I can rename across many files like I did with VS Code's search
    panel.
14. As a backend/web developer, I want to run HTTP requests from `.http` files
    inside the editor, so that I can test APIs next to the code that calls
    them, with the request files committed alongside the project.
15. As a user, I want a project-wide diagnostics/quickfix list, so that I can
    see and jump through all errors and warnings in one panel.
16. As a user, I want to extract a function or variable from a selection, so
    that I can refactor with a command instead of manual edits.
17. As a user, I want to inline a variable, so that I can reverse an extraction
    quickly.
18. As a user coming from VS Code, I want to change the same word in many
    places without a plugin, so that I keep the config lean while getting the
    multi-edit workflow (native `cn`/`cN` + `.`, and visual-block).
19. As a user, I want column/multi-line edits via visual-block, so that I can
    edit aligned lines simultaneously.
20. As a user, I want to jump to any function or method in the current file by
    name, so that I can navigate a large class quickly (document symbols, VS
    Code's Ctrl+Shift+O).
21. As a user, I want to search symbols across the whole workspace, so that I
    can find a definition anywhere in the project (workspace symbols, Ctrl+T).
22. As a user, I want a command palette, so that I can fuzzy-find and run
    editor commands and keymaps.
23. As a user, I want inline parameter/type hints (inlay hints) on by default
    with a toggle, so that I get WebStorm-style parameter visibility and can
    silence it with one key when it's noisy.
24. As a user, I want the parameter popup as I type a function call (signature
    help), so that I can see arguments without a plugin (via blink.cmp).
25. As a user, I want to expand/shrink a selection by syntax node, so that I
    can grow a selection structurally (WebStorm's Ctrl+W).
26. As a user, I want function/class *definition* text objects, so that I can
    operate on whole functions and classes with `af`/`ac` (via mini.ai +
    treesitter, no new plugin).
27. As a user, I want to add/change/delete surrounding quotes/brackets/tags,
    so that I can restructure delimiters quickly (mini.surround).
28. As a web developer, I want HTML/JSX/Vue/Svelte tags to auto-close and
    auto-rename, so that tag editing is painless (nvim-ts-autotag).
29. As a user, I want the current function/class signature pinned at the top
    while scrolling a long body, so that I keep context (treesitter-context).
30. As a user, I want a jump motion to hop anywhere on screen by label, so
    that I navigate within a buffer faster (flash.nvim).
31. As a CSS/Tailwind/Svelte/Vue developer, I want inline colour swatches for
    hex/rgb/Tailwind classes, so that I can see colours in the buffer
    (nvim-highlight-colors).
32. As a user, I want indent guides, so that I can read nesting at a glance
    (snacks.indent, no new plugin).
33. As a user, I want context-aware commenting in JSX/Vue/Svelte, so that
    `gc` comments land correctly in embedded regions.
34. As a user, I want richer code folding: files open unfolded, folds provided
    by LSP then treesitter then indent, with a readable fold summary and a
    peek, so that folding feels IDE-grade (tuned nvim-ufo).
35. As a user, I want a fold gutter with clickable markers, so that I can see
    and toggle folds visually (foldcolumn on).
36. As a user, I want `]`/`[` navigation for diagnostics, git hunks and todo
    comments, so that I can move between them without commands.
37. As a user, I want to toggle inline git blame, so that I can see authorship
    on demand.
38. As a user, I want a terminal toggle keybind, so that I can drop to a shell
    without leaving the editor (snacks.terminal).
39. As a user, I want to close a buffer without closing its window, so that my
    layout survives buffer churn (snacks.bufdelete).
40. As a user, I want an organise-imports action, so that I can clean up
    imports via the LSP.
41. As a user, I want a todo-comments list, so that I can see all TODO/FIXME
    markers project-wide (via trouble).
42. As a user, I want my `<leader>` group prefixes to follow a familiar
    convention (find/git/code/search/ui/debug/diagnostics/refactor/rest), so
    that muscle memory transfers and which-key stays discoverable.
43. As the fleet maintainer, I want to add a new language by adding one row to
    a registry table, so that LSP, treesitter, formatter, linter and debug
    adapter are wired from a single place (ADR 0141).
44. As the fleet maintainer, I want to remove a language by deleting one row,
    so that nothing drifts out of sync across specs.
45. As the fleet maintainer, I want the abandoned `nvim-emmet` dropped and
    Emmet served by the existing `emmet_language_server` LSP, so that I remove
    dead single-maintainer code with no feature loss.
46. As the fleet maintainer, I want every adopted plugin to be actively
    maintained with real community behind it, so that I don't build on a
    plugin that gets archived (multicursor.nvim was dropped for exactly this,
    resolved with native keybinds).
47. As a user, I want all of the above to lazy-load, so that cold startup
    stays fast and "fewer plugins do most of the job" holds.
48. As a user on KDE / no compositor, I want the theme behaviour unchanged —
    static Catppuccin Mocha Sapphire, follow off by default — so that this
    expansion does not disturb the theme story (ADR 0136).
49. As the fleet maintainer, I want the static-config test seam extended to
    assert every new plugin, keymap and the registry, so that regressions are
    caught without booting nvim.
50. As the fleet maintainer, I want the runtime acceptance gate extended so
    the debug adapters must resolve on PATH and `:checkhealth dap` is clean,
    so that a host without the adapters fails the gate.

## Implementation Decisions

- **Foundation unchanged.** Stays a hand-rolled lazy.nvim config on stable
  Neovim 0.12.x (ADR 0135). No LazyVim distro, no `vim.pack`, no `mason`.
- **Plugins added (all lazy-loaded):** diffview.nvim; nvim-dap with nvim-dap-ui
  (and its nvim-nio dep) plus the thin config-wrappers nvim-dap-python and
  nvim-dap-go; trouble.nvim; kulala.nvim; mini.surround; nvim-ts-autotag;
  nvim-treesitter-context; flash.nvim; nvim-highlight-colors; refactoring.nvim;
  grug-far.nvim. Each fills a distinct gap; lazy triggers on filetype / command
  / keys / event so startup cost stays ~zero.
- **Plugin removed:** nvim-emmet (abandoned, single-maintainer, and redundant
  with the already-installed `emmet_language_server` LSP).
- **Multi-cursor is native, not a plugin.** multicursor.nvim and
  vim-visual-multi were both rejected on bus-factor grounds; the VS Code
  multi-edit workflow is provided by native keymaps (`cn` = `*``cgn`, `cN` =
  `#``cgN`, a visual variant, plus visual-block `I`/`A`/`c` and the existing
  `<leader>rw`).
- **Config-only capabilities (no new plugins):** mini.ai wired with treesitter
  text objects for `af`/`ac` (function/class definitions); snacks.indent
  enabled for indent guides; native `vim.lsp.inlay_hint` default **on** with a
  `<leader>uh` toggle; blink.cmp signature help enabled; treesitter
  incremental selection; context-aware commenting for JSX/Vue/Svelte; document
  + workspace symbol pickers, command palette, organise-imports,
  blame-toggle, `]`/`[` navigation, terminal toggle and buffer-delete keymaps.
- **Language Registry (ADR 0141).** A single table keyed by language is the
  source of truth; the lsp / conform / lint / dap specs consume it instead of
  carrying inline lists. Row shape (encodes the decision):

  ```lua
  ["<language>"] = {
    lsp        = "<lspconfig server name>",     -- or nil
    treesitter = { "<parser>", ... },           -- parsers to install
    formatter  = { "<conform formatter>", ... },-- or nil
    linter     = { "<nvim-lint linter>", ... }, -- or nil
    dap        = "<adapter key>",               -- or nil
  }
  ```

  The registry is **data, not behaviour**: each consumer still maps a row into
  its own plugin shape (`vim.lsp.enable`, conform's `formatters_by_ft`,
  nvim-lint's `linters_by_ft`, dap `adapters`/`configurations`). All current
  languages are kept; none added or removed by this work.
- **Debugging (ADR 0140).** nvim-dap covers the **core five**: python
  (debugpy), go (delve), rust + c/c++ (codelldb — one adapter for all three),
  js/ts (js-debug). Adapter **binaries** install as **system packages** in
  **Host Core `packages.language-servers`** beside the LSP servers,
  arch-wiki-grounded — not mason-nvim-dap. PHP (xdebug) and Zig are out of
  scope, addable later as a one-row registry entry.
- **Git.** diffview.nvim is scoped to merge-conflict resolution and
  file/branch history (`:Diffview*` commands); lazygit remains the daily
  driver and gitsigns is unchanged.
- **Keybinds.** Hybrid: `<leader>` group prefixes align to the LazyVim
  convention (find `f`, git `g`, code `c`, search `s`, ui `u`, debug `d`,
  diagnostics `x`, refactor `r`, rest/API `R`) and are registered as which-key
  groups; existing leaf bindings are kept. Config is personal — optimise for
  the maintainer's muscle memory, which-key retained for the maintainer's own
  discoverability.
- **Theme unchanged (ADR 0136).** `follow_noctalia` stays default false; the
  static default remains Catppuccin Mocha Sapphire; the five-builtin 1:1
  mapping and lualine `theme = "auto"` are untouched. No ADR 0136 reversal.
- **Performance contract.** "Feature-packed and performant" resolves to: add
  the feature but it must lazy-load to ~zero startup; a feature that cannot be
  made cheap/lazy is cut.

## Testing Decisions

- **What a good test is here:** assert observable, external config behaviour —
  that the committed config *declares* a capability (plugin present with a lazy
  trigger, keymap mapped, registry consumed, package declared) or that a booted
  nvim *exhibits* it — never internal implementation shape. Follow the existing
  per-ticket organisation and grep-the-committed-spec style.
- **Seam A — static config (primary), `.installer/tests/config/nvim-program.bats`:**
  extend with assertions for every new plugin and its lazy trigger; the removed
  nvim-emmet; the native multi-cursor keymaps; snacks.indent; the inlay-hint
  default-on flag and `<leader>uh` toggle; foldcolumn + tuned ufo; the
  `<leader>` group prefixes; the new keymaps (symbols, command palette,
  organise-imports, blame toggle, `]`/`[` nav, terminal, bufdelete); the
  **Language Registry** table existing and the lsp/conform/lint/dap specs
  consuming it; and Host Core declaring the DAP adapter packages. Correct the
  now-inaccurate assertions in this file (neo-tree, fugitive, nvim-emmet).
  Prior art: the whole existing file (kitty-program.bats, lazygit-program.bats
  are sibling static seams).
- **Seam B — runtime acceptance, `.installer/tests/nvim/checkhealth.sh` +
  `probe.lua`:** add the four adapter binaries (codelldb, debugpy, delve,
  js-debug — under their Arch package binary names) to checkhealth's `required`
  PATH list and gate on a clean `:checkhealth dap`; optionally extend probe.lua
  to assert inlay hints default on and that a registry-listed server enables.
  Prior art: the existing checkhealth ERROR gate + LSP-on-PATH loop, and the
  probe's theme-state assertions. Run on the arch-combined VM verify-block.
- **No new seam is introduced.** The two existing seams cover all of this.

## Out of Scope

- Any theme change: follow-default, static default palette, the five-builtin
  mapping, lualine styling all stay as they are (ADR 0136).
- Debugging for PHP (xdebug) and Zig; testing framework integration
  (neotest); noice.nvim; dropbar breadcrumbs; session restore
  (persistence.nvim) — all deliberately deferred, each a cheap later add.
- Adding or removing any language from the current set.
- Replacing lazygit; diffview complements it.
- A full VS Code parity pass beyond the gaps enumerated above.
- Switching to `vim.pack` (revisited only when 0.13 stabilises, ADR 0135).

## Further Notes

- Bus-factor was checked with live GitHub data (contributors, last-commit,
  archived) for every current and proposed plugin. Findings that shaped this
  spec: `nvim-emmet` is abandoned (1 contributor, ~2.3y idle) and redundant →
  dropped; `diffview.nvim` is dormant (~2.1y idle) but has 36 contributors and
  is the stable de-facto standard → kept with eyes open; `multicursor.nvim`
  is effectively solo → dropped in favour of native keybinds. All other
  adopted plugins are actively maintained.
- Sequencing (for `/to-tickets`): a natural slice order is registry →
  debugging (dap + Host Core packages) → git (diffview) → trouble → API
  (kulala) → editor UX plugins (surround/autotag/ts-context/flash/
  highlight-colors) → refactoring → grug-far → config-only ergonomics (inlay
  hints, incremental selection, folding, keymaps, which-key groups) → drop
  nvim-emmet → tests (Seams A + B) → docs already landed (ADRs 0140/0141 +
  CONTEXT.md).
- ADRs 0140 (nvim-dap + system-package adapters) and 0141 (Language Registry)
  and the CONTEXT.md [[Neovim Config]] / [[Language Registry]] entries are
  already written (status: pending implementation).
