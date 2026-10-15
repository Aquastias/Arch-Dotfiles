# 02: Schema owns every config default; menu and seed derive from it

**What to build:** the Install Config schema declares path, type and default
for every Effective Config field anyone reads — adding rows for fields it
lacks today (e.g. `options.swap_size`, `options.pacman.*`, `post_install.*`,
`sysctl`). Guided menu field rows keep only section + label and name their
schema row; the guided seed defaults come from the schema. A default lives in
exactly one place. Decisions: candidate #1, Q16.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Every menu field resolves its default from a schema row
- [x] Seed defaults derive from the schema
- [x] Test: no default declared outside the schema
- [x] Guided menu renders identically (existing guided suite green)

## Comments

2026-10-15: Split found two kinds of "default": Install Defaults (absent →
X at install) and Guided Launch Presets (identity, mode, timezone, desktop,
fonts, Security & Backup Extras — absent installs something else). Only the
first moved to the schema (CONTEXT.md: both terms). Schema gains a `number`
type, comma-listed array defaults, rows swap_size/stock/gpu/locales/keymaps/
mirror_countries/optional_repos/kernels (4 specials deleted, 2 read their
default from the row); `install_config_default`, `_default_object`,
`_schema_names`. Seed: install defaults from the schema, presets named.
Menu: schema-owned rows carry no default; derived via the schema (locale
projection too). Feature Audit coverage stopped reading the private menu
table — uses `menu_rows '{}' '{}'`. Seed + menu output byte-identical
(empty and seeded baseline, diffed before/after). Tests:
install-config-defaults.bats (6), 2 menu invariant tests; config, guided,
packages, feature-audit suites green.
