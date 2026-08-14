# 05 — Console font leaf, applied to vconsole

**What to build:** A `console font` leaf under **Locales** backed by a new
first-class `system.console_font` field, applied to `/etc/vconsole.conf`. The
operator picks from the fonts actually installed on the medium
(`/usr/share/kbd/consolefonts`); an off-list value is rejected. The default is
`default8x16` (always present via `kbd` in `base`), so an untouched install never
boots to a broken console. Independent of the language/encoding work — can run in
parallel with 03/04.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] `system.console_font` is a schema-validated Host Profile field: it joins the
      closed-schema allowlist, the accessors, and install-state; an unknown value
      is rejected at load.
- [ ] A `console font` leaf appears in **Locales**, default `default8x16`, with the
      `●` flag tracking only real overrides.
- [ ] `menu_enum_options` for the console-font leaf returns the locale-source font
      list (from `/usr/share/kbd/consolefonts`), stubbable in tests.
- [ ] An override is validated against the enumerated list (picker semantics like
      `keyboard`); an off-list value is rejected rather than written.
- [ ] The identity Chroot Configuration Module writes `FONT=<console_font>` into
      `/etc/vconsole.conf` alongside `KEYMAP=`.
- [ ] `CONSOLE_FONT` round-trips through install-state alongside
      `LOCALE`/`KEYMAP`/`TIMEZONE`.
- [ ] Tests: font enumeration + validation (stubbed source), the leaf row, the
      vconsole `FONT=` write, and the install-state round-trip. Prior art:
      `tests/config/menu-enum.bats`, `tests/chroot/chroot-configure.bats`,
      `tests/install-state.bats`.
