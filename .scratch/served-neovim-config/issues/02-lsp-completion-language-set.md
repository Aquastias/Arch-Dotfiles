# 02: LSP + completion for the full language set

**What to build:** Every in-scope language gets a real LSP and modern
completion. nvim-lspconfig fronting native `vim.lsp.config`/`vim.lsp.enable`
(0.12), blink.cmp for completion, plus lazydev + fidget. The `dev/nvim` program
grows the **extra toolchain as system packages** (no `mason`), repo where
possible and AUR for gaps. Opening a file in any of html/css/js/ts/react/svelte/
solid/vue/php/json/yaml/python/lua/rust/zig/nix/go/c/c++ attaches its server;
solid rides the ts server; Swift is best-effort and never blocks.

**Blocked by:** 01.

**Status:** done

- [x] Program adds: lua-language-server, basedpyright, nil, phpactor,
      svelte-language-server, vue-language-server (Volar),
      tailwindcss-language-server, emmet-language-server (repo/AUR,
      arch-wiki-grounded). Existing Host Core servers are reused, not duplicated.
- [x] Each in-scope language attaches its LSP; hover/definition/references work.
- [x] blink.cmp completion + signature + docs work (screen 3 of the prototype).
- [x] Swift/sourcekit-lsp wiring is guarded — a missing AUR package does not
      break the config or `:checkhealth`.
- [x] `:checkhealth` LSP section shows every enabled server reachable; zero
      ERROR.
