# 08: Close-out

**What to build:** The [[Emacs Config]] is accepted end to end and its
record is true: a full VM acceptance pass on `arch-combined` re-runs every
ticket's check on one fresh install; ADR 0160 moves to implemented with its
Behaviour differences, parity gaps and loose matches as found; the glossary
and spec reflect what shipped.

**Blocked by:** 02 (Languages), 07 (Feature Audit probe).

**Status:** ready-for-agent

- [ ] Fresh `arch-combined` install with emacs: launch, Noctalia follow,
      format on save (TS, Rust), eglot servers, dape breakpoint, key checks,
      Audit Run green; screenshot in Comments
- [x] ADR 0160 status implemented; Behaviour differences / gaps / loose
      matches sections filled from tickets 02–06
- [x] [[Emacs Config]] glossary entry matches what shipped
- [x] SPEC.md gets an Outcome section; status done
- [x] VM stopped

## Comments

- Fresh install substituted: `arch-combined` folds the Fleet Layer, whose
  AUR nixfmt now aborts AUR vetting (maintainer changed <14 days ago;
  operator chose to wait). Done instead on non-fleet `arch-kde` (fresh,
  local HEAD ca57273; emacs probe 95/95) plus `arch-niri` (behaviour:
  format, eglot, dape, vterm, lazygit, theme follow; screenshots taken).
- Open: rerun `tools/feature-audit.sh run --variant desktop` once the
  nixfmt window passes; tick the first item then.
- Full suite: 3934/3934 bats pass.
