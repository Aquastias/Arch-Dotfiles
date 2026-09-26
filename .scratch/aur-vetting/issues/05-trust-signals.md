# 05: Trust signals

**What to build:** one AUR RPC `info` lookup per package base, feeding
findings:
- maintainer differs from the one recorded with the Vetted Commit:
  critical;
- orphan adoption or first submission under 14 days ago: suspicious;
- out of date or low votes: info.

RPC failures retry with backoff (ADR 0052 pattern), then abort when
unattended. When interactive, the vetter asks whether to continue without
trust signals. The RPC endpoint is overridable by a fixture JSON for tests.
See PRD stories 31-33, 51, 52.

**Blocked by:** 04.

**Status:** done

- [ ] A maintainer-change fixture aborts even with an otherwise clean,
      bump-only diff.
- [ ] Orphan-adoption and new-package fixtures produce suspicious findings.
- [ ] An RPC-down fixture retries (sleep shadowed in tests), then aborts
      when unattended.
- [ ] Tests never touch the real network.
