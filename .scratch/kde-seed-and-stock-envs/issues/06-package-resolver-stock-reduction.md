# 06 — Package Resolver stock reduction

**What to build:** Under `environment.stock`, the [[Package Resolver]] reports the
reduced package set — the KDE app/seed sets and the Noctalia preset sets are
absent — so `tools/explain-packages.sh` and the Guided Installer's read-only
`derived` view tell the truth about what a stock install lands. (ADR 0112.)

**Blocked by:** 03 (`environment.stock` foundation — the resolved flag it reads).

**Status:** ready-for-agent

- [ ] `lib/packages/resolver.sh` omits the `kde-shell` app sets for a stock KDE
      config and reports the plasma shell only.
- [ ] It omits the Noctalia [[Wayland Shell Companion]] preset sets for a stock
      compositor config.
- [ ] `tests/packages/resolver.bats` asserts both reductions.
- [ ] `explain-packages` and the guided `derived` view reflect the reduction
      (they consume the resolver, so no separate wiring — verify no drift).
