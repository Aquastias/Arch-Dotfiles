# 01 — Program kind marker → `kind` enum

**What to build:** Every Program Config declares its nature positively as
`"kind": "host" | "user"` instead of the `"system": true|false` bool, and the
[[Program Registry]] reports that kind as `host | user | none`. A Host Program
author writes `"kind": "host"`; a User Program author writes `"kind": "user"`;
a program config that omits `kind` or uses an out-of-set value aborts at
registry build with an actionable message naming the program. Every kind-driven
consumer — the Guided Installer's two program pickers, the ADR 0036 user →
Host Program reconciliation, and ADR 0065 `requires` ordering — works under the
new value with no behaviour change to what installs.

**Blocked by:** None — can start immediately.

**Status:** done (commit 92fea73)

- [x] All 18 Program Configs carry `"kind": "host" | "user"`; no `"system"`
      flag remains in any program config.
- [x] Registry build reads `kind`; an absent or out-of-set `kind` aborts at
      load naming the offending program (regression: a config still using
      `"system"` aborts).
- [x] `program_kind <name>` returns `host | user | none`; `program_names_of_kind
      host` enumerates Host Programs; all `== "system"` comparison sites move to
      `== "host"`.
- [x] The Guided host-program picker offers only `kind: host` programs and the
      User Editor picker only `kind: user`.
- [x] User → Host Program reconciliation (shadow / no-op / abort) and `requires`
      ordering pass under the new value.
- [x] The existing config, guided, and validation bats suites assert the new
      value and stay green.

## Comments

- 2026-09-27 audit: 92fea73.
