# 06 — Package Resolver stock reduction

**What to build:** Under `environment.stock`, the [[Package Resolver]] reports the
reduced package set — the KDE app/seed sets and the Noctalia preset sets are
absent — so `tools/explain-packages.sh` and the Guided Installer's read-only
`derived` view tell the truth about what a stock install lands. (ADR 0112.)

**Blocked by:** 03 (`environment.stock` foundation — the resolved flag it reads).

**Status:** done

- [x] `lib/packages/resolver.sh` omits the `kde-shell` app sets for a stock KDE
      config and reports the plasma shell only.
- [x] It omits the Noctalia [[Wayland Shell Companion]] preset sets for a stock
      compositor config.
- [x] `tests/packages/resolver.bats` asserts both reductions.
- [x] `explain-packages` and the guided `derived` view reflect the reduction
      (they consume the resolver, so no separate wiring — verify no drift).

## Comments

- 2026-09-27 doc sync: shipped in 6dfb331, 3918ff4, b34e8da, 11d0e5c, 96de292,
  577586f (ADR 0111-0115).
