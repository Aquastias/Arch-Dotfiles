# Guided Installer: Locales category recut

Status: ready-for-agent

Recuts the Guided Installer's **Locales** Category into four leaves — `keyboard`,
`language`, `encoding`, `console font` — with `language`/`encoding` as
projections of the single canonical `system.locale`, a new `system.console_font`
field, and live option enumeration from the installer medium. Timezone stays out
of Locales; its category is renamed **System → General**. See ADR 0076 and the
**Locales Category** / **General Category** glossary terms in `CONTEXT.md`.

## Problem Statement

As an operator using the Guided Installer, my localization choices are exposed as
just two coarse rows under **Locales**: `locale` (a single `en_US.UTF-8` string
bundling language and encoding) and `keymap`. I cannot pick language and encoding
independently, I cannot set the virtual-console font at all (the installer always
leaves `/etc/vconsole.conf` without a `FONT=`, and the `locale.gen` charset is
hardcoded to `UTF-8`), and the options I do get are not the real, complete set
the live medium can offer. Meanwhile timezone sits under a category named
**System** even though it is a clock setting, not localization.

## Solution

Split **Locales** into four discrete leaves that mirror archinstall's Locales
submenu: `keyboard`, `language`, `encoding`, and `console font`. Language and
encoding are two editable *views* of one canonical locale string, so the profile
keeps a single source of truth and no `en_US.UTF-8.UTF-8` double-suffix can ever
be authored. Add a real console-font field applied to `/etc/vconsole.conf`.
Enumerate every leaf's options live from the installer medium, filtering encoding
to the charsets valid for the chosen language. Keep timezone where it belongs —
its own concern — and rename its category from **System** to **General**.

## User Stories

1. As an operator, I want **Locales** to list `keyboard`, `language`,
   `encoding`, and `console font` as separate leaves, so that I can tune each
   aspect of localization on its own.
2. As an operator, I want the `keyboard` leaf to set the console keymap, so that
   my keys are mapped correctly from first boot.
3. As an operator, I want the `language` leaf to set the base locale (e.g.
   `en_US`), so that my system language is what I chose.
4. As an operator, I want the `encoding` leaf to set the character encoding (e.g.
   `UTF-8`), so that my locale is generated with the right charset.
5. As an operator, I want editing `language` or `encoding` to update the single
   underlying locale string, so that the two views never disagree and the
   profile stays canonical.
6. As an operator, I want it to be impossible to produce a doubled encoding
   suffix (e.g. `en_US.UTF-8.UTF-8`), so that my locale always generates.
7. As an operator, I want the `encoding` leaf to offer only encodings valid for
   the language I picked, so that I cannot author a locale `locale-gen` cannot
   build.
8. As an operator, I want a `console font` leaf, so that I can set the
   virtual-console font instead of always getting the kernel default.
9. As an operator, I want the console font to default to a font that is always
   present, so that an untouched install never boots to a broken console.
10. As an operator, I want the console-font choices to be the fonts actually
    installed on the medium, so that every option I can pick is loadable.
11. As an operator, I want an invalid console-font value to be rejected, so that
    a typo cannot leave me with a garbled or blank console at boot.
12. As an operator, I want the keyboard, language, and encoding lists to reflect
    the complete, current set the live medium supports, so that my choices are
    not limited by a stale hardcoded list.
13. As an operator, I want the default locale (`en_US.UTF-8`), keymap (`us`), and
    console font (`default8x16`) preserved when I do not touch them, so that a
    blank-start install still works.
14. As an operator seeding from a Host Profile that pins multiple locales or
    keymaps, I want the Locales leaves to edit the default (first) entry while
    leaving the rest intact, so that guided edits never silently drop authored
    locales.
15. As an operator, I want the `●` override dot on a Locales leaf only when I
    have actually changed it, so that I can see at a glance what I touched.
16. As an operator, I want the Locales category preview to summarize its four
    leaves' current values, so that I can review localization without drilling
    in.
17. As an operator, I want timezone to remain outside Locales, so that a clock
    setting is not conflated with localization.
18. As an operator, I want the category holding hostname and timezone to be named
    **General**, so that its name reflects that it is no longer localization.
19. As an operator, I want my chosen encoding to drive both the `locale.gen`
    entry and `LANG`, so that a non-UTF-8 locale is generated correctly rather
    than silently coerced to UTF-8.
20. As an operator with a desktop selected, I want my keyboard choice to continue
    to drive the X11 keyboard layout, so that my layout is consistent across the
    console and the desktop.
21. As a profile author, I want `system.console_font` to be a first-class,
    schema-validated Host Profile field, so that I can pin a console font
    declaratively and have an unknown value rejected at load.
22. As a maintainer, I want the projection (compose/decompose of the canonical
    locale) to live in one shared place, so that the interactive controller and
    the replay editors can never drift on how language/encoding map to the
    locale string.

## Implementation Decisions

- **Locales leaves.** The Locales Category surfaces four leaves: `keyboard`
  (relabels the existing `system.keymap`), `language`, `encoding`, and
  `console font` (new `system.console_font`). `keyboard`'s label changes; its
  underlying path stays `system.keymap`.
- **Canonical locale + projections.** `system.locale` remains the single
  persisted field (scalar|array union, default `en_US.UTF-8`). `language` is the
  base before the charset suffix; `encoding` is the suffix. A shared
  compose/decompose helper in the Menu model is the sole owner of splitting
  `system.locale` into `{language, encoding}` and recomposing them back into one
  string — recomposing exactly once. Both guided front-ends (the interactive
  controller and the replay editors) call this helper, so they cannot drift.
- **No schema split.** `system.language` / `system.encoding` are NOT added to the
  schema; they exist only as menu-level views. This preserves every committed
  profile, install-state, and the string-or-array multi-locale contract (ADR
  0076, considered-and-rejected: schema split).
- **New field.** `system.console_font` (scalar, default `default8x16`) joins the
  closed-schema allowlist, the accessors, and install-state in lockstep. It is
  written as `FONT=` in `/etc/vconsole.conf` by the identity Chroot
  Configuration Module.
- **Charset derivation.** The identity module derives the `locale.gen` charset
  column and `LANG` from the locale string instead of hardcoding `UTF-8`, so a
  chosen non-UTF-8 encoding is honoured.
- **Array semantics.** Where `system.locale` / `system.keymap` are arrays
  (element 0 = default), the Locales leaves edit element 0 and leave any
  remaining entries untouched.
- **Live enumeration via a new source seam.** A thin **locale-source** boundary
  provides the option lists — a small set of functions
  (`locale_list_keymaps`, `locale_list_languages`, `locale_list_encodings
  <language>`, `locale_list_console_fonts`). In production they read the live
  medium: keymaps via `localectl list-keymaps`, languages/encodings from
  `/usr/share/i18n/SUPPORTED`, console fonts from `/usr/share/kbd/consolefonts`.
  `menu_enum_options` calls this layer instead of returning static lists for the
  four leaves.
- **Encoding filtered by language.** `encoding`'s option source takes the current
  `language` as input and returns only the charsets `/usr/share/i18n/SUPPORTED`
  pairs with it — the one signature change to the enumeration path. An unbuildable
  language+encoding pair therefore cannot be selected.
- **Console-font validation.** A `console font` override is validated against the
  enumerated font list (picker semantics, like `keymap`); an off-list value is
  rejected rather than written. The ISO and target font sets are identical (`kbd`
  is in `base`), so there is no legitimate off-list value.
- **Category rename.** The category previously named **System** (hostname +
  timezone) is renamed **General**. Timezone stays in it; it is not moved to
  Locales and does not get its own category. ADR 0071's frozen category list is
  amended in name only; 0071 is left intact (ADR-0074 precedent).
- **Order preserved.** Locales remains first in the archinstall-reading-order
  category list; **General** keeps the slot **System** held.

## Testing Decisions

Good tests here assert only **external behavior** — the rows and option lists the
Menu model emits, the files the chroot module writes, and the state it persists —
never internal structure. The rows ARE the contract.

- **Menu model (primary seam, existing).** Extend `menu_rows` / `menu_categories`
  / `menu_enum_options` tests. Assert: the four Locales leaves appear with
  correct labels; the `General` category name (and that `System` no longer
  appears); `language`/`encoding` render as the decomposed parts of a canonical
  `system.locale`; editing either recomposes to exactly one string (no doubled
  suffix); the `●` override flag tracks only real overrides. Prior art:
  `tests/config/guided-menu.bats`, `tests/config/menu-enum.bats`.
- **Compose/decompose helper (primary seam, existing).** Unit-test the shared
  locale helper directly at the Menu-model seam: round-trip `en_US.UTF-8` ↔
  `{en_US, UTF-8}`; a non-UTF-8 pair; an array whose element 0 is edited while
  the tail is preserved. Prior art: `tests/config/menu-enum.bats` style
  (pure, JSON/string in/out).
- **Locale-source boundary (new seam).** The enumeration functions are stubbed /
  pointed at fixtures in tests so no live ISO is required. Assert:
  `menu_enum_options` for each leaf returns the fixture list; `encoding` returns
  only charsets paired with the passed language; defaults surface when a source
  is empty. Prior art: `tests/config/menu-enum.bats`.
- **Chroot identity module (existing seam).** Assert the module writes the
  `locale.gen` line with the charset derived from the locale (not a hardcoded
  `UTF-8`), `LANG` matching, and `FONT=<console_font>` in `/etc/vconsole.conf`.
  Prior art: `tests/chroot/chroot-configure.bats`.
- **Install-state (existing seam).** Assert `CONSOLE_FONT` is carried through the
  install-state round-trip alongside `LOCALE`/`KEYMAP`/`TIMEZONE`. Prior art:
  `tests/install-state.bats`.

## Out of Scope

- Any schema split of `system.locale` into separate language/encoding fields
  (explicitly rejected — ADR 0076).
- Multi-select of multiple locales/keymaps in the Guided Installer; guided edits
  the default (element 0) only. Multi-locale authoring remains a hand-authored
  Host Profile capability.
- Moving timezone into Locales, or giving timezone its own category.
- Per-user or per-desktop locale/keymap; this is machine-wide system identity.
- Changing the X11 keyboard-layout behavior beyond it continuing to follow the
  keymap list.
- Retro-editing ADR 0071 or other ADRs; the rename is recorded as a delta in
  ADR 0076.

## Further Notes

- archinstall reference: its Locales submenu is exactly these four leaves
  (keyboard, language, encoding, console font); timezone is a separate top-level
  item; console-font default is `default8x16`; encoding is derived from
  `/usr/share/i18n/SUPPORTED`. The double-suffix bug this design avoids is
  archinstall issue #1413 (they stored language and encoding as two overlapping
  fields).
- The projection design means the profile continues to store one canonical
  locale string; the split only exists at the menu surface.
