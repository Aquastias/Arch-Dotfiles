# Guided Installer: inline-masked credentials + per-user editor

---
Status: accepted
---

The Guided Installer captures passwords by typing **inline in the fzf query
line, masked as `••••`**, instead of dropping to an `execute()` prompt that
takes over the screen. Real characters are held in a tmpfs buffer via a
`transform-query` bind (rebound only on password screens so it never masks
hostname / sysctl); the visible query renders bullets. Entry is confirmed
type-twice. Cursor movement (Left/Right/Home/End/click) is **unbound on password
screens** so only append + backspace-at-end are possible — the buffer can never
desync (mid-string edits are impossible, not merely caught by the confirm). On an
fzf too old for the masking binds, it **degrades to the ADR 0049 `execute()`
masked prompt** — never broken, just out-and-back, reusing the version-gate
pattern of ADR 0047's rich chrome.

The Users screen is **flattened**: entering `Users` lands directly on the
root-password row, each user (enabled shown `name — shell · pw ⚠`, disabled shown
`name — disabled`, no checkbox), `＋ Create user`, and `← Back` — no intermediate
`users: aquastias` row. The top-screen `Users`
category row carries a `⚠ N pw needed` signal (and the `Proceed` row reads
blocked) while root or any enabled user lacks a password, so the requirement is
visible before drilling in.

Enter on a user opens a **User Editor**: enabled/remove, shell, password, sudo,
groups, git identity, SSH keys, programs — the full User Profile. Edits are
**install-scoped**: they bake into Proceed (patching the user's profile on the
install clone) and Export, but a committed `users/<name>/profile.jsonc` in the
repo is **never rewritten** — preserving the "Save never overwrites committed"
invariant (ADR 0036 / guided-save). The editor shows a committed user's
*effective* (core-merged) values while storing only a delta. Save is not silent
about the gap: when a committed user carries install-only profile edits, Save
**warns** and names them (edit the committed file to persist), then writes the
device-less profile as usual.

Disabling the last user is permitted — a root-only install is a legitimate,
reachable state (no hard userless guard; `post_install_guard_users` blocks it
only when Security/Backup Extras are selected), made usable by the now-prominent
root password. A newly-created user defaults to shell `bash`, `sudo: on`,
`groups: [wheel]`; this also unifies the two prior disagreeing defaults (the
replay create path's `sudo:false` and the materialize fallback's `sudo:true`).

Amends ADR 0049 (in-menu credentials): the handoff-file shape, the no-SOPS
manifest path, and the in-menu Proceed gate all stand; only the *masked-entry
surface* changes (query-buffer primary, `execute()` fallback). Scope is the
root + per-user passwords only — the ZFS encryption passphrase keeps its
back-end prompt, and the INSTALL / ACCEPT gates stay typed tty confirmations.
(The passphrase carve-out is **superseded by ADR 0054**: the passphrase is now
captured inline in the Disks screen, with the back-end prompt kept as fallback.)

## Considered Options

### Masked entry surface
- **Query-line buffer trick** — chosen. Stays inside the one persistent fzf
  (the reported annoyance was leaving it) *and* stays masked. Robust for
  append + backspace; the fragile mid-string-edit case does not arise for
  password typing.
- **Unmasked query line** — rejected. Fully inline and trivial, but a visible
  root password is a secrecy regression over today's `read -s`.
- **Keep `execute()` only** — rejected as the primary path (it is the drop-out
  the user dislikes) but **retained as the old-fzf fallback**.

### Committed-user profile edits
- **Install-scoped, never rewrite committed** — chosen. The installed user gets
  the chosen shell/etc.; the operator's committed source stays pristine. A
  Saved profile does not remember a committed user's field edit (`.users` is
  names-only) — accepted, since the Save path is the reuse/audit artifact, not
  the per-install tweak surface.
- **WYSIWYG — Save rewrites `users/<name>/profile.jsonc`** — rejected. Breaks
  the "Save never overwrites committed" rule and mutates checked-in source.

## Consequences

- Replay is unchanged: it never enters fzf, still supplying passwords via keyed
  answers into the held-aside vars.
- The masking binds + the User Editor's live edits need a real tty/fzf; they are
  driven automatically by the PTY smoke harness (`tools/guided-fzf-smoke.py`,
  which sends keystrokes to `guided-preview.sh` and asserts rendered screens), so
  the check is repeatable and AFK rather than a human gate. The pure logic (buffer
  accumulate/backspace, delta authoring, effective-view render, completeness
  predicate) is bats-covered.
- The User Editor subsumes the old bare `＋ Create user` (name-only) flow:
  creating a user lands in the editor so shell / password / sudo are set at
  once, and a name without a committed profile still materializes a default
  (bash + wheel) if left untouched.
