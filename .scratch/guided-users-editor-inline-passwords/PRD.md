# Guided Installer: Users redesign + inline masked passwords

Status: done (slices 283188e, 66bffea, afd97de, caf8cc4, 4d3edee)

Amends ADR 0049; specified in ADR 0051. Builds on ADR 0042 (persistent-fzf
controller), ADR 0047 (in-menu binding + rich-chrome version gate), ADR 0036
(device-less Effective Config, users names-only).

## Problem Statement

Two friction points in the Guided Installer's Users flow:

1. Entering `Users` shows only `users: aquastias`. The operator has no idea a
   **root** account exists or that a password is required until they drill two
   levels deep — or until Proceed blocks them. They can't see everything at a
   glance, and they're not told where passwords are needed.
2. Setting a password drops the operator **out of fzf** into a full-screen
   `execute()` prompt, then back in. The context switch is jarring; the operator
   wants to type the password **inline, masked, without ever leaving fzf**.

Additionally, the operator wants to **see and change a user's shell** (and other
profile fields) during install — impossible today, since the persistent menu
can't edit any per-user profile data.

## Solution

Redesign the Users area and the credential capture surface:

- **Flatten** the Users screen so entering `Users` shows everything directly: a
  root-password row, every user (with inline shell + password status), a create
  action, and back — no intermediate `users:` row.
- Surface a **`⚠ N pw needed`** signal on the top-level `Users` category row and
  mark `Proceed` blocked while any required password is unset, so the requirement
  is visible before drilling in.
- Give each user a **User Editor** (Enter opens it) exposing the full User
  Profile — enabled/remove, shell, password, sudo, groups, git, SSH keys,
  programs. Edits are **install-scoped**: they take effect on the installed
  machine but never rewrite committed repo files.
- Capture passwords **inline in the fzf query line, masked as `••••`**, with a
  type-twice confirm, degrading to today's `execute()` masked prompt only on an
  fzf too old for the masking binds.

## User Stories

1. As an operator, I want to see the root account the moment I enter Users, so
   that I know it exists and needs a password.
2. As an operator, I want the Users screen to list every user directly, so that
   I don't have to drill through a `users:` row to see them.
3. As an operator, I want a `⚠ N pw needed` marker on the top-level Users row, so
   that I know a password is outstanding before I ever open Users.
4. As an operator, I want the Proceed row to read as blocked while passwords are
   missing, so that I understand why I can't install yet.
5. As an operator, I want each user row to show its shell and password status
   inline (e.g. `aquastias — zsh · pw ⚠`), so that I can assess the account at a
   glance.
6. As an operator, I want to press Enter on a user to open an editor, so that I
   can change its settings.
7. As an operator, I want to change a user's shell in the editor, so that the
   installed user logs into that shell.
8. As an operator, I want bash to be the default shell, so that an untouched user
   behaves as before.
9. As an operator, I want to toggle a user's sudo in the editor, so that I control
   its privileges.
10. As an operator, I want to edit a user's groups, git identity, SSH authorized
    keys, and programs, so that the whole User Profile is adjustable in-menu.
11. As an operator, I want a committed user's editor to show its effective
    (core-merged) values, so that I see the real current settings, not a blank
    delta.
12. As an operator, I want my per-user edits to take effect on the installed
    machine (Proceed) and in an exported config, so that the changes are real.
13. As an operator, I want my committed `users/<name>/profile.jsonc` left
    untouched by an in-menu edit, so that my checked-in source stays pristine.
14. As an operator, I want Save to warn me when a committed user carries
    install-only edits, so that I'm not surprised that a saved profile reinstalls
    with the old values.
15. As an operator, I want to disable a committed user, so that it is excluded
    from this install without being deleted.
16. As an operator, I want to create an ad-hoc user, so that I can add an account
    that isn't committed to the repo.
17. As an operator, I want `＋ Create user` to drop me straight into the editor,
    so that I set the required password (and other fields) immediately.
18. As an operator, I want a new user to default to shell bash, sudo on, and the
    wheel group, so that the common personal-machine case needs no extra clicks.
19. As an operator, I want to remove an ad-hoc (session-created) user, so that I
    can undo a creation.
20. As an operator, I want a disabled user shown as `name — disabled` (no
    checkbox), so that its state is clear without a control that looks toggleable
    but isn't.
21. As an operator, I want to build a root-only install by disabling the last
    user, so that I can provision a server without a personal account.
22. As an operator building a root-only install, I want Proceed still blocked if I
    selected Security/Backup Extras, so that I don't create an un-installable
    config.
23. As an operator, I want to type the root password directly in the fzf query
    line, so that I never leave the menu.
24. As an operator, I want the password rendered as `••••` while I type, so that
    it isn't shoulder-surfable.
25. As an operator, I want to type each password twice, so that a typo I can't see
    is caught before install.
26. As an operator, I want a password mismatch to show a notice and let me retry
    inline, so that I recover without leaving fzf.
27. As an operator, I want backspace to work while typing a masked password, so
    that I can correct the end of what I typed.
28. As an operator, I want cursor keys disabled on password screens, so that I
    can't accidentally corrupt the masked value with a mid-string edit.
29. As an operator on an older ISO whose fzf can't do the masking binds, I want a
    working masked prompt (the previous out-and-back), so that installation is
    never broken.
30. As an operator, I want the Users list, the top-level `⚠`, and the Proceed
    gate to agree on which passwords are missing, so that the signals are
    consistent.
31. As an operator, I want passwords to stay out of the Config State, so that
    Save/Export never carry a plaintext secret.
32. As an operator running a scripted (replay) install, I want password + per-user
    fields supplied via keyed answers, so that headless installs keep working
    without a tty.
33. As an operator, I want undo/redo/reset to cover my Users edits like any other
    edit, so that mistakes are recoverable.

## Implementation Decisions

**Modules built / modified** (no new fzf-side complexity beyond the masking glue):

- **Menu model (`menu.sh`)** — add a `⚠ N pw needed` fold to the `Users` category
  row in `menu_categories`, computed from the completeness predicate the same way
  the `●` override flag is folded. The count is root (if unset) plus each enabled
  user lacking a password.
- **Controller (`guided-controller.sh`)** — the primary work:
  - Flatten the Users `values` screen: root-password row, per-user rows rendered
    `name — shell · pw <ok|⚠>` (enabled) or `name — disabled`, `＋ Create user`,
    `← Back`. No `users: aquastias` category-level row.
  - New **User Editor** nav screen (`useredit`, addressed by user name): rows for
    enabled (committed) / remove (ad-hoc), shell (cycle bash/zsh/fish), password,
    sudo (toggle), groups (multi), git name/email (text), SSH keys (list),
    programs (multi). Enter on a user opens it; Enter on root password opens the
    masked entry.
  - `enabled` toggles a committed user in/out of `.users`; `remove` deletes a
    session-created user. A committed user is never removable; an ad-hoc user has
    no `enabled` row.
  - `＋ Create user` → name text screen → lands in the User Editor with defaults
    shell bash, sudo on, groups [wheel].
  - Mark the top `Proceed` row blocked (`Proceed ▸ set passwords first ⚠`) while
    the completeness predicate reports any missing password; keep the existing
    in-menu Proceed gate (notice + bell) unchanged.
  - Password entry: on capable fzf the row navigates to a masked text screen that
    rebinds `change:transform-query` to the masking translator and unbinds cursor
    movement (Left/Right/Home/End/click); on an older fzf it falls back to the
    ADR 0049 `execute()` masked prompt. Reuse the ADR 0047 version-gate pattern
    (`GUIDED_RICH_CHROME`-style cached flag) to decide.
- **Masking (NEW pure fn, e.g. `guided_mask_apply`)** — reconstructs the real
  buffer from the previous buffer + the new query string: a longer query appends
  its non-bullet suffix; a shorter query pops from the end. Returns the updated
  buffer and the bullet display string. The fzf `transform-query` bind and cursor
  unbind are thin glue over this pure core.
- **Per-user profile edits** — the User Editor authors a per-user delta via the
  existing `guided_user_profile` (prune empties, drop name). Committed users load
  their effective (core-merged) profile for *display* but store only the delta in
  a session per-user form map (like `_GUIDED_ADHOC_FORM`, extended to committed
  users). At Proceed the delta is materialized onto the **install clone's**
  `users/<name>/profile.jsonc`; the repo copy is never written.
- **Save-warn (NEW pure predicate)** — given the session per-user forms and the
  set of committed users, return the committed users carrying non-empty deltas.
  `guided_save_host_profile`'s caller warns (naming them) but still writes the
  device-less profile; it never rewrites `users/<name>/profile.jsonc`.
- **Secrets-file (`guided-secrets-file.sh`)** — unchanged shape and completeness
  predicate (`guided_secretsfile_missing`) drive the list `⚠`, the top-level
  count, and the Proceed gate — one source of truth.

**Contracts / invariants preserved:**

- `.users` stays **names-only**; no profile data enters the Config State (ADR
  0036). Passwords never enter the Config State (ADR 0042/0049).
- Save never overwrites committed source (ADR 0036 / guided-save); the new warn
  makes the install-only gap explicit rather than silent.
- Replay path keeps supplying passwords + per-user fields via keyed answers.

## Testing Decisions

Good tests here exercise **external behavior at the controller/model seam** —
state files in, rendered list / directive / new state out — never the fzf glue.
The live masking bind, cursor unbind, and `execute()` fallback are driven
automatically by the existing **PTY smoke harness** (`tools/guided-fzf-smoke.py`),
which sends keystrokes to `guided-preview.sh` inside a pty and asserts the rendered
screens — so the previously-human "live fzf render" check is repeatable and AFK.

- **`guided_mask_apply` (new, pure)** — the highest-value new tests: append one
  char, append several (paste), backspace, backspace-to-empty, and a would-be
  mid-string case proving the buffer stays consistent under the append/backspace
  contract. Prior art: `guided-secrets-file.bats`.
- **Controller Users screen** — the flattened list rendering (root row, enabled
  vs `disabled` suffix, `＋ Create user`), Enter-opens-editor dispatch, `enabled`
  toggle, `remove` on ad-hoc, create-lands-in-editor with the bash/sudo/wheel
  defaults. Prior art: `guided-controller.bats`, `guided-users.bats`.
- **User Editor edits** — shell cycle, sudo toggle, groups/git/ssh/programs
  authoring produce the expected per-user delta via `guided_user_profile`; a
  committed user renders effective values but stores only a delta. Prior art:
  `guided-shell.bats`, `guided-users.bats`, `guided-emit.bats`.
- **Menu `⚠` fold** — `menu_categories` marks the Users row with the right count
  under various set/unset password states. Prior art: `guided-menu.bats`.
- **Save-warn predicate (new, pure)** — returns exactly the committed users with
  non-empty deltas; empty when none. Prior art: `guided-save.bats`.
- **Proceed gate consistency** — the list `⚠`, the top count, and the gate all
  derive from `guided_secretsfile_missing` over the same effective users. Prior
  art: `guided-secrets.bats`, `guided-secrets-file.bats`.

## Out of Scope

- The **ZFS encryption passphrase** — keeps its back-end `prompt_secret`; not
  pulled into the menu.
- The typed **INSTALL / ACCEPT** consent gates — stay bare-tty confirmations
  (they are consent, not secrets).
- **Persisting** a committed user's field edit into a Saved reusable profile —
  install-scoped only; the operator edits the committed file to persist (Save
  warns).
- **Reveal toggle** for masked entry — not built (masked, no reveal).
- **Mid-string masked editing** — intentionally impossible via cursor lock, not a
  feature to support.
- Any change to the **back-end** password/secrets consumption path — the handoff
  file shape and manifest round-trip are unchanged.

## Further Notes

- The `＋ Create user` → editor flow subsumes the old name-only create; a name
  left untouched still materializes the default profile (bash + wheel) at Proceed.
- Disabling the last user is a legitimate root-only install; the existing
  `post_install_guard_users` is the only block (extras selected → no primary user
  to run the paru pass).
- Unify the two disagreeing new-user sudo defaults (replay create `sudo:false`,
  materialize fallback `sudo:true`) on **sudo on / wheel**.
