# Inline masked password entry in fzf (root + user)

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-users-editor-inline-passwords/PRD.md` (ADR 0051).

## What to build

Replace the `execute()` drop-out password prompt with **inline, masked entry in
the fzf query line** for the root password row and the user password row (in the
User Editor). The operator types in the query line, which renders as `••••`; the
real characters are kept in a tmpfs buffer.

Pure core — a `guided_mask_apply <buffer> <new-query>` that reconstructs the real
buffer from the previous buffer plus the new query string: a longer query appends
its non-bullet suffix; a shorter query pops from the end. Returns the updated
buffer and the bullet display string. This is bats-covered.

Live glue — on capable fzf, the password screen rebinds
`change:transform-query` to the masking translator and **unbinds cursor movement**
(Left/Right/Home/End/click) so only append + backspace-at-end are possible and the
buffer can never desync. Entry is confirmed **type-twice**; a mismatch shows a
notice and lets the operator retry inline. On an fzf too old for the masking binds,
degrade to the ADR 0049 `execute()` masked, confirmed prompt (reuse the ADR 0047
version-gate cached-flag pattern). Captured secrets continue to flow through the
existing handoff file — never the Config State — so Save/Export stay secret-free,
and the replay path (keyed answers) is unaffected.

## Acceptance criteria

- [ ] `guided_mask_apply` bats: append one char, append several (paste),
      backspace, backspace-to-empty, and a consistency case under the
      append/backspace contract.
- [ ] On capable fzf, typing a root or user password renders `••••` inline; the
      captured value equals what was typed; cursor keys are inert on the screen.
- [ ] Type-twice confirm: matching entries save; a mismatch shows a notice and
      re-prompts without leaving fzf.
- [ ] On an fzf below the gate, entry falls back to the `execute()` masked,
      confirmed prompt and still succeeds.
- [ ] Captured passwords never appear in the Config State, Save, or Export.
- [ ] Replay installs still supply passwords via keyed answers (no tty), unchanged.
- [ ] The PTY smoke harness (`tools/guided-fzf-smoke.py`, extended) drives the
      password screen and asserts: query renders `••••`, the captured value equals
      the keystrokes, cursor keys are inert, a type-twice mismatch re-prompts, and
      the old-fzf fallback path is taken when the version flag is forced off.

## Blocked by

- `01-flatten-users-toplevel-warn.md`
- `03-editor-full-fields-create-into-editor.md`
