# ADR 0009: Persist materialization verbs omit data movement

## Status
Accepted

## Context
`persist_apply` (write Persist Mount unit + tmpfiles + reload) and
`persist_unapply` (tear it down) have two consumers with asymmetric data
semantics:

- **Install-time** (`lib/chroot/impermanence.sh`) stages live data onto
  the Persist Dataset via `mv` — the rolled-back dataset will lose any
  live copy on next boot anyway.
- **Runtime tool** (`tools/impermanence.sh add`) stages via `cp -a` —
  the bind mount activates immediately, so the original must remain
  until covered.

The runtime `remove` verb is also asymmetric: by default it leaves
`/persist/<path>` untouched (safe); `--yes` opts into moving data back.

## Decision
`persist_apply` and `persist_unapply` only materialize / tear down the
Persist Mount itself. Data movement is the caller's responsibility,
exposed as separate helpers:

- `persist_stage_in_move` — install-time staging (move)
- `persist_stage_in_copy` — runtime add staging (copy)
- `persist_restore_data` — runtime `remove --yes` (move back)

Consumers compose explicitly: install loops over `persist_stage_in_move`
+ `persist_apply`; runtime `add` calls `persist_stage_in_copy` +
`persist_apply`; runtime `remove --yes` calls `persist_unapply` +
`persist_restore_data`.

## Considered alternatives
**Bundle data movement into the verbs.** Forces a `mode=install|runtime`
knob on `persist_apply` and a `move_back=yes|no` knob on
`persist_unapply`. Both become context-dependent; default safety on
`remove` (no data destruction without explicit opt-in) would require
inverting today's `--yes` flag into a `--no-move` flag.

## Consequences
- The `cp` vs `mv` choice is visible at every call site, not buried in
  a verb's mode parameter.
- `persist_unapply` is safe by default — no data loss possible without
  a separate, explicit `persist_restore_data` call.
- Adding a new consumer (e.g. "promote runtime extension to curated
  default") means composing existing primitives, not extending a shared
  verb's signature.
