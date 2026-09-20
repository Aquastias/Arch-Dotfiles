# 03: Format + lint

**What to build:** Formatting via conform and diagnostics via nvim-lint, with
the toolchain installed as system packages by the `dev/nvim` program.
Format-on-save and lint diagnostics follow project config per filetype.

**Blocked by:** 02.

**Status:** done

- [x] conform maps: biome (js/ts/jsx/tsx/json/css), prettier (html/svelte/vue/
      yaml/md), stylua (lua), ruff (python), native rustfmt/gofmt/`zig fmt`.
- [x] nvim-lint provides biome/ruff diagnostics where the LSP does not, gated on
      the project carrying the relevant config (e.g. `biome.json`).
- [x] Program adds the formatter/linter packages (stylua, prettier, ruff; biome
      already present).
- [x] Format-on-save produces the same output the CLI tool would; no format war
      with the LSP.
- [x] `:checkhealth` conform/lint sections show tools found; zero ERROR.
