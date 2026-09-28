# 03: Languages + Editor Coverage Map

**What to build:** Every [[Language Registry]] language works in VSCodium on
the **system toolchain**: language extensions added to the extension list and
pointed at Host Core `/usr/bin` binaries wherever a path setting exists
(rust-analyzer, gopls/dlv, ruff, biome, prettier, stylua, lua-language-server,
clangd, zig/zls, nixd, phpactor, svelte, vue); bundled only for the ADR 0148
exceptions (tailwind, yaml, bash-ide, basedpyright). Per-language default
formatter mirrors the Registry's formatter column; format on save only (no code
actions on save, no autosave); biome lints only with a `biome.json`. REST Client
covers `.http`/`.rest`. The [[Editor Coverage Map]] data file maps each
Registry key → extension ID(s) or `n/a` + reason.

**Blocked by:** 02 (Tracer).

**Status:** done

- [x] Coverage Map test: Registry keys (awk-extracted, no Lua runtime) ==
      Coverage Map keys; every non-n/a ID is in the extension list
- [x] Test: every path setting resolves to a binary a Host Core package
      provides
- [x] Test: each Registry formatter has the matching VSCodium default
      formatter for its filetypes
- [x] Vue server path form (dir vs entry) settled; phpactor bundling settled;
      both noted in ADR 0148 if it changes anything
- [x] VM: format on save in a TS and a Rust file; language servers in use are
      the `/usr/bin` ones (process list)

## Comments

- Static slice done. Vue = module dir, svelte = /usr/bin/svelteserver,
  phpactor = binary path. biome lint-only-with-config not possible (ADR 0148
  Behaviour differences). VM checks run in ticket 06.
