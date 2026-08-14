# 02 — Locale-source seam + keyboard leaf enumerates live keymaps

**What to build:** A thin **locale-source** boundary that supplies the Locales
leaves' option lists from the installer medium, and the first leaf built on it:
`keyboard`. The existing `keymap` field is relabelled `keyboard`, and its option
list is the medium's real keymap set (`localectl list-keymaps`) instead of a
hardcoded/absent list. This is the prefactor the language, encoding, and console
font tickets reuse — "make the change easy, then make the easy change".

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A locale-source layer exists as a small set of functions callable by the
      Menu model; `locale_list_keymaps` returns the medium's keymaps in
      production and is stubbable/fixturable in tests (no live ISO required).
- [ ] The `keyboard` leaf (path still `system.keymap`) appears in **Locales**
      with that label; `keymap` as a label no longer shows.
- [ ] `menu_enum_options` for the keyboard leaf returns the locale-source keymap
      list rather than a static list.
- [ ] The interactive controller and the replay editors both pick the keyboard
      value from this list (no drift between the two front-ends).
- [ ] The default keymap (`us`) is preserved when the operator does not touch it;
      the `●` override flag tracks only real overrides.
- [ ] Tests stub the locale source and assert the enumerated keyboard list and
      the leaf row. Prior art: `tests/config/menu-enum.bats`,
      `tests/config/guided-menu.bats`.
