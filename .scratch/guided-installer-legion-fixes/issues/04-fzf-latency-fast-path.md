# 04 — fzf menu-switch latency fast-path

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-installer-legion-fixes/PRD.md`

## What to build

Cut the per-navigation cost so switching between menus feels immediate,
without changing the ADR-0042 single-persistent-fzf architecture or any
rendered output.

Today each menu switch blocks on two bash forks: `dispatch` (source the
controller, compute the action) then the returned `reload(bash entry list)`
(source the controller again, rebuild the list, fan out several jq calls).

Changes:
- Navigation dispatch computes the next screen's list once, writes it to a
  file, and returns `reload(cat <file>)` — replacing the second bash+source
  fork with a cheap `cat`.
- Collapse the list builder's jq fan-out into far fewer jq invocations.

Rendered rows must be byte-identical before and after (behavior-preserving);
this slice only changes speed.

## Acceptance criteria

- [ ] Menu navigation returns `reload(cat <file>)` instead of re-forking bash
      to rebuild the list.
- [ ] The list builder issues materially fewer jq invocations per render.
- [ ] `guided_ctl_list` emits identical rows per screen before and after the
      change (output-equivalence bats).
- [ ] The architecture is unchanged (still one persistent fzf + stateless
      subprocesses); no new long-lived process.
- [ ] Felt latency improvement confirmed at the HITL/VM gate on the Legion.

## Blocked by

- `.scratch/guided-installer-legion-fixes/issues/01-display-label-formatter.md`
- `.scratch/guided-installer-legion-fixes/issues/03-in-menu-credentials.md`

(Both edit the same render/dispatch paths as this slice; land them first so the
output-equivalence baseline reflects final row content and to avoid conflicts.)
