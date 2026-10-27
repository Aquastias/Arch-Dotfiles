# 02: Languages, toolchain, coverage map

**What to build:** Every [[Language Registry]] language works in Emacs on
the same system toolchain as nvim (ADR 0160, ADR 0148 contract). LSP via
Doom's eglot flavour on servers from PATH (never auto-downloaded); Doom
`lang` modules (or packages) per Registry row; format on save via apheleia
with conform's formatter per language, no fix-all on save, organize imports
on `SPC c o`; linting via flymake; `]d`/`[d` diagnostics. An [[Editor
Coverage Map]] for Emacs keeps it in step with the Registry.

**Blocked by:** 01 (Tracer).

**Status:** done

- [x] `init.el` enables `lsp +eglot`, `format +onsave`, flymake checkers and
      the Registry's `lang` modules; no lsp-mode
- [x] eglot server commands point at system binaries where Doom's defaults
      differ; formatter map mirrors conform
- [x] Emacs coverage map: one row per Registry key → module/package or
      `n/a <reason>`
- [x] Static bats: coverage keys equal Registry keys (awk, no Lua/Emacs
      runtime); module flags present; lsp-mode absent
- [x] VM: format on save in a TS and a Rust file uses the system formatters;
      eglot attaches the `/usr/bin` servers; noted in Comments
- [x] Mismatches with nvim recorded for ADR 0160 Behaviour differences

## Comments

- Every Registry server is set explicitly via `set-eglot-client!` (system
  binary, checked against the Fleet Layer in bats). web-mode serves html,
  .svelte and .vue, so its contact picks the server by file extension.
- Doom's lua module passes Doom-local args to lua-language-server; the
  override runs `after! lua-mode` so it lands later.
- `format +onsave` without `+lsp` (that flag hands formatting to the server).
  phpcbf (PSR-12) and kdlfmt are custom apheleia formatters.
- Linters: flymake-ruff (python), flymake-biome only under biome.json/.jsonc.
- Gaps for ADR: tailwind and eslint servers (eglot runs one server per
  buffer). Vue's server v3 expects tsserver forwarding that eglot lacks —
  confirm in VM; likely a loose match.
- VM check batched (see ticket 01 note).

- VM (arch-niri): a.ts → biome `const x = { a: 1 };`, b.rs → rustfmt; eglot
  runs /usr/bin typescript-language-server, rust-analyzer,
  basedpyright-langserver; c.tsx → typescript-tsx-mode. doom doctor: 0
  errors, 14 warnings (Doom-native extras outside nvim parity).
