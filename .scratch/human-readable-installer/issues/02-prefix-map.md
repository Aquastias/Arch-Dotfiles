# 02: Prefix Map

**What to build:** Every installer file gets its new public/private Prefix
in one table in the readability doc, approved once by the owner. File-stem
rule; a directory forming one public API (Feature Audit, Guided Installer)
lends its name to public functions. Interface Functions listed by glossary
role (`root_adapter_*`, `data_formatter_*`). Resolves the `install_`
(config accessors vs Install State) and `_guided_`/`_ctl_` clashes. The
lint's Prefix rule switches on, existing mismatches baselined.

**Blocked by:** 01 — Readability Lint

**Status:** ready-for-human

- [ ] Table covers every installer `.sh` (lib, entry scripts, vm, tools,
      extras, program install scripts)
- [ ] Owner approved
- [ ] Prefix rule + fixture tests (wrong/missing Prefix caught; Interface
      Function allowed); baseline updated; suite green

## Comments

- Draft map written to `docs/agents/readability.md` (Prefix Map). Waiting on
  owner approval; Prefix lint rule lands after.
