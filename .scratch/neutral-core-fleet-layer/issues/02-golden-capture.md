# 02: Golden capture and desktop ≡ laptop guard

**What to build:** before any layer moves, freeze what the operator's two
machines install today, so every later ticket proves "no change" against it.
Capture the resolved Effective Config (devices/secrets masked) and the full
install set (with ticket 01's sources) for `desktop` and `laptop` as committed
golden fixtures, plus a permanent test that the two resolve to the same
install set ([[ADR 0114]] invariant). See PRD and [[ADR 0157]].

**Blocked by:** 01 (Package Resolver reports Host Programs and User Programs)

**Status:** done

- [x] Golden fixtures for `desktop` and `laptop` committed (config + set)
- [x] A bats test diffs the live resolution against the goldens and passes on
      today's tree
- [x] A bats test asserts `desktop` and `laptop` install sets are equal
- [x] The golden test is documented as the "no change" gate for 04, 05, 07, 08
