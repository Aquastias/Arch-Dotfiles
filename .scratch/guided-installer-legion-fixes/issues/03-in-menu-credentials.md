# 03 — In-menu credential entry (replaces post-menu prompt)

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-installer-legion-fixes/PRD.md`

## What to build

Move root and per-user password entry inside the Guided Installer menu, so the
installer never drops out to a bare terminal after Proceed. Supersedes ADR
0042's "passwords collected post-menu at Proceed" decision while preserving its
core invariant: passwords never enter the Config State, so Save/Export never
write a plaintext secret.

Behavior:
- The Users screen grows a `root password` row and, under each enabled user,
  an indented `password` row. Selecting one opens a masked, read-twice,
  confirmed prompt (non-empty; no minimum length — unchanged) via the existing
  fzf `execute()` drop-out, then returns to the menu.
- Because the prompt runs in a subprocess that cannot write the parent shell's
  variables, the captured secret is handed back through a dedicated tmpfs file
  (`GUIDED_SECRETS_FILE`, created by the persistent-fzf launcher via mktemp and
  cleaned by the same RETURN trap as the other GUIDED_*_FILE files). Shape:
  `{ root_password?: str, users?: { <name>: { password: str } } }`.
- This file is never referenced by config emit, Save, or Export. The parent
  reads it at Proceed to build the existing no-SOPS password manifest;
  `.secrets.*` stays untouched (guided remains no-SOPS).
- Rows display `(set)` / `(not set)`, derived from the file, never the value.
- Proceed is gated inside fzf: a completeness predicate reports any missing
  credential (root + every enabled user). On the Proceed key, a `transform`
  bind evaluates it — if incomplete, update the header/notice with the missing
  items + bell and do NOT accept (stay in the menu); if complete, write the
  terminal action and accept. Save/Export are not gated.
- The old post-menu collection path is removed. Replay continues to inject
  passwords via keyed answers (this is an interactive-only change).

## Acceptance criteria

- [ ] Users screen shows a `root password` row and an indented `password` row
      under each enabled user; selecting one opens a masked, confirmed prompt
      and returns to the menu.
- [ ] Captured passwords land in `GUIDED_SECRETS_FILE` in the documented shape
      and are read at Proceed to build the no-SOPS manifest.
- [ ] Config emit, Save, and Export never contain any password;
      `.secrets.*` is untouched.
- [ ] Rows show only `(set)` / `(not set)`.
- [ ] Proceed refuses in-menu (header notice + bell, no exit) while root or any
      enabled user password is unset, and proceeds once all are set;
      Save/Export are never gated.
- [ ] The post-menu password prompt is gone; replay still supplies passwords
      via keyed answers.
- [ ] bats covers the manifest read/write shape, the completeness predicate
      (missing vs complete), and the emit/Save/Export secret-free assertion.
- [ ] Live masked prompt + in-fzf gate verified at the HITL/VM gate.

## Blocked by

None - can start immediately.
