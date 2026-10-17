# 08: Neutral fonts and mirrors

**What to build:** nobody inherits the operator's fonts or mirror countries.
The Font Catalog's default-checked set becomes noto, dejavu, liberation; the
`mirror_countries` Install Default becomes empty and the Mirror Service then
ranks mirrors worldwide (no country filter). The Fleet Layer carries today's
full font selection and country list. See PRD and [[ADR 0157]].

**Blocked by:** 04 (Fleet Layer)

**Status:** done

- [x] Golden test (02) passes unchanged for `desktop` and `laptop`
- [x] A non-fleet profile resolves only the three neutral font families
- [x] Empty countries produce a valid worldwide reflector configuration
- [x] Guided Fonts and Mirrors rows show the new defaults with no ●
- [x] fonts / mirrors bats updated; CONTEXT.md Font Catalog and Mirror
      Service entries updated
