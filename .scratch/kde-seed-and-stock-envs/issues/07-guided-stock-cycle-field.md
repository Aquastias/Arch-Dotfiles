# 07 — Guided stock Cycle Field

**What to build:** The [[Guided Installer]]'s Environment Configuration Category
gains a `stock` [[Cycle Field]] — a bare bool that flips in place (Enter toggles,
no drill), default off — so the operator can choose a stock environment from the
menu without editing a profile. Its `derived` preview reflects the reduced set.
(ADR 0112.)

**Blocked by:** 03 (`environment.stock` foundation). Soft: 06 (so the `derived`
preview shows the reduced set accurately).

**Status:** done

- [x] A `stock` Cycle Field appears in the Environment category, default off,
      flipping in place with the standard override dot (ADR 0075).
- [x] Flipping it writes `environment.stock` into Config State; flipping back to
      the default clears the override.
- [x] The change bakes into Proceed / Save Profile / Export like any environment
      field.
- [x] Guided controller tests assert the field flips, stores, and normalises out
      at default.
- [x] The Environment `derived` preview reflects the stock reduction (via the
      resolver from ticket 06).

## Comments

- 2026-09-27 doc sync: shipped in 6dfb331, 3918ff4, b34e8da, 11d0e5c, 96de292,
  577586f (ADR 0111-0115).
