# 04 — Encoding leaf, filtered by language, charset honoured end-to-end

**What to build:** An editable `encoding` leaf under **Locales**, plus the chroot
change that makes a chosen encoding actually take effect. The encoding leaf offers
only the charsets valid for the currently-chosen `language` (from
`/usr/share/i18n/SUPPORTED`), so an unbuildable locale cannot be authored. The
identity Chroot Configuration Module derives the `locale.gen` charset column and
`LANG` from the locale string instead of hardcoding `UTF-8`, so a non-UTF-8
encoding is generated correctly.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] An `encoding` leaf appears in **Locales**, rendering the charset suffix of
      the current `system.locale` (e.g. `UTF-8`).
- [ ] The encoding option source takes the current `language` and returns only the
      charsets `/usr/share/i18n/SUPPORTED` pairs with it; an invalid
      language+encoding pair cannot be selected.
- [ ] Editing `encoding` recomposes `system.locale` via the shared helper (exactly
      once; element-0 semantics preserved for arrays).
- [ ] The identity module writes the `locale.gen` line with the charset derived
      from the locale (not a hardcoded `UTF-8`), and `LANG` matching.
- [ ] A non-UTF-8 encoding selection results in that locale being generated.
- [ ] Tests: encoding enumeration filtered by language (stubbed source); identity
      module writes the derived charset + LANG. Prior art:
      `tests/config/menu-enum.bats`, `tests/chroot/chroot-configure.bats`.
