# Locales is four leaves projected from one canonical locale string

Status: accepted (amends ADR 0071's category names — renames **System** to
**General**; extends ADR 0039/0071's Locales section)

The Guided Installer's **Locales** Category becomes four leaves — `keyboard`,
`language`, `encoding`, `console font` — mirroring archinstall's Locales
submenu. `keyboard` is the existing `system.keymap` relabelled. `language` and
`encoding` are **projections** of the single canonical `system.locale` string
(`en_US.UTF-8`): language is the base before the charset suffix, encoding is the
suffix. Editing either recomposes `system.locale` exactly once, so the profile
keeps one source of truth and archinstall's `en_US.UTF-8.UTF-8` double-suffix
bug (their issue #1413, from storing language and encoding as two overlapping
fields) is structurally impossible. `console font` is a **new** scalar field,
`system.console_font`, written as `FONT=` in `/etc/vconsole.conf` (default
`default8x16`, always present via `kbd` in `base`).

Options enumerate live from the installer medium, not from static lists:
keyboard via `localectl list-keymaps`, language and encoding from
`/usr/share/i18n/SUPPORTED`, console font from `/usr/share/kbd/consolefonts`.
`encoding` is filtered to the charsets `SUPPORTED` pairs with the current
`language`, so an unbuildable locale cannot be authored. `identity.sh` now
derives the `locale.gen` charset column and `LANG` from the locale string
instead of hardcoding `UTF-8`. Where `system.locale`/`system.keymap` are arrays
(element 0 = default), the leaves edit element 0 and leave the rest intact.

Timezone stays **out** of Locales — it is a clock setting, and archinstall
likewise keeps it a separate top-level item. Its category, now holding only
hostname + timezone, is renamed **System → General**.

## Considered options

- **Split the schema** into `system.language`/`system.encoding`/
  `system.keyboard` — rejected: breaks every committed profile, install-state,
  and the string-or-array multi-locale contract, and it is exactly the
  two-overlapping-fields shape that gave archinstall its double-suffix bug.
- **Static option lists** (like kernels / mirror countries) — rejected: keymaps
  (~250) and languages (~500) are too many to curate and drift with the ISO.
- **Global encoding list** (archinstall's behaviour) — rejected: lets an
  operator author a language+encoding pair not in `SUPPORTED`, which
  `locale-gen` cannot produce. Filtering per language is correct by
  construction.
- **Free-text console font** — rejected: the ISO and target font sets are
  identical (`kbd` is in `base`), so an off-list value is only ever a typo that
  breaks the console at boot; validate against the glob like `keymap`.
- **A dedicated Timezone category** — rejected: a whole category for one field;
  hostname + timezone under **General** is enough.

## Consequences

- `system.console_font` becomes committed Host Profile surface: it joins the
  closed-schema allowlist (`profile.sh`), the accessors, and `install-state.sh`
  in lockstep.
- `menu_enum_options` gains its first **runtime-sourced** options; the encoding
  source additionally reads the current `language`, so those leaves are no
  longer purely path-keyed.
- ADR 0071's frozen category list is amended in name only (System → General);
  0071 itself is left intact, per the ADR-0074 precedent.
