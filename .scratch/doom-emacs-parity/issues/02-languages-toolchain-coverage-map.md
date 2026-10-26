# 02: Languages, toolchain, coverage map

**What to build:** Every [[Language Registry]] language works in Emacs on
the same system toolchain as nvim (ADR 0160, ADR 0148 contract). LSP via
Doom's eglot flavour on servers from PATH (never auto-downloaded); Doom
`lang` modules (or packages) per Registry row; format on save via apheleia
with conform's formatter per language, no fix-all on save, organize imports
on `SPC c o`; linting via flymake; `]d`/`[d` diagnostics. An [[Editor
Coverage Map]] for Emacs keeps it in step with the Registry.

**Blocked by:** 01 (Tracer).

**Status:** ready-for-agent

- [ ] `init.el` enables `lsp +eglot`, `format +onsave`, flymake checkers and
      the Registry's `lang` modules; no lsp-mode
- [ ] eglot server commands point at system binaries where Doom's defaults
      differ; formatter map mirrors conform
- [ ] Emacs coverage map: one row per Registry key → module/package or
      `n/a <reason>`
- [ ] Static bats: coverage keys equal Registry keys (awk, no Lua/Emacs
      runtime); module flags present; lsp-mode absent
- [ ] VM: format on save in a TS and a Rust file uses the system formatters;
      eglot attaches the `/usr/bin` servers; noted in Comments
- [ ] Mismatches with nvim recorded for ADR 0160 Behaviour differences

## Comments
