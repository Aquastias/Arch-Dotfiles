# 03 — Language leaf as a projection of the canonical locale

**What to build:** A `language` leaf under **Locales** that is an editable view of
the single canonical `system.locale` string — its base before the charset suffix.
A shared compose/decompose helper (the sole owner of splitting `system.locale`
into `{language, encoding}` and recomposing them) lets the operator pick a
language from the medium's real language set; editing recomposes `system.locale`
exactly once, keeping the existing encoding suffix and preserving any multi-locale
array tail (element 0 is edited, the rest untouched). No schema field is added —
`language` exists only as a menu-level view.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] A `language` leaf appears in **Locales**, rendering the base of the current
      `system.locale` (e.g. `en_US` for `en_US.UTF-8`).
- [ ] A shared compose/decompose helper in the Menu model round-trips
      `system.locale` ↔ `{language, encoding}`; both guided front-ends use it (no
      drift).
- [ ] `menu_enum_options` for the language leaf returns the locale-source language
      list (`/usr/share/i18n/SUPPORTED`), stubbable in tests.
- [ ] Editing `language` recomposes `system.locale` exactly once — the encoding
      suffix is preserved and never doubled (no `en_US.UTF-8.UTF-8`).
- [ ] When `system.locale` is an array, editing `language` changes element 0 and
      leaves remaining entries intact.
- [ ] Default locale (`en_US.UTF-8`) preserved when untouched; `●` tracks only
      real overrides.
- [ ] Tests cover the helper round-trip (incl. a non-UTF-8 pair and an array) and
      the language row/enumeration. Prior art: `tests/config/menu-enum.bats`,
      `tests/config/guided-menu.bats`.
