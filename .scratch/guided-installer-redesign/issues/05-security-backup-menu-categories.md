# Security & Backup menu categories + no-user guard

Status: done

## Parent

`.scratch/guided-installer-redesign/PRD.md`

## What to build

Wire the **Security** and **Backup** Configuration Categories into the
two-level menu so the operator chooses what installs, authoring the
structured `post_install.{security,backup}` objects the back-end consumes.

Security category: a firewall radiolist (firewalld / ufw / none — single
choice; firewalld and ufw are mutually exclusive), plus toggles for antivirus
(clamav), rootkit (rkhunter) and apparmor. Backup category: toggles for
zfs-auto-snapshot and borg. A fresh guided run pre-ticks firewalld + clamav +
rkhunter + apparmor and zfs-auto-snapshot + borg (the secure baseline from
the resolver default).

Terminal-action guard (M5): when `post_install.security` or
`post_install.backup` resolves to a non-empty Program list but the host has
no users, the terminal action (Proceed / Save / Export) aborts with an
actionable message ("security/backup install via paru and need a primary
user — add a user or clear the selections").

## Acceptance criteria

- [x] Security / Backup are top-level categories; drilling in shows the
      firewall radiolist + tool toggles.
- [x] The firewall is single-choice; the choice + toggles emit a valid
      structured `post_install.security` / `post_install.backup` object.
- [x] A fresh guided run pre-ticks firewalld + clamav + rkhunter + apparmor
      and zfs-auto-snapshot + borg.
- [x] With selections set and zero users, Proceed / Save / Export abort with
      the actionable message; with a user, or with empty selections, they
      pass.
- [x] bats for the no-user guard (prior art `tests/config/validation-*.bats`)
      and stubbed-fzf bats for the Security / Backup editors.
- [x] VM smoke (guided replay): driving the Security / Backup categories
      installs the selected daemons in the booted system. **DONE 2026-06-22 —
      see Comments.**

## Blocked by

- `.scratch/guided-installer-redesign/issues/02-two-level-category-menu.md`
- `.scratch/guided-installer-redesign/issues/04-security-backup-extras-backend.md`

## Comments

**DONE via /tdd (2026-06-21).** Security/Backup categories wired into the
two-level menu; AC1-5 done, VM smoke (AC6) deferred (no VM).

**M3 seed** (`seed.sh`): `cfgstate_seed_defaults` now seeds `post_install =
post_install_default` into the **baseline** layer — a fresh run pre-ticks
firewalld + clamav + rkhunter + apparmor + zfs-auto-snapshot + borg, shown with
no ● (baseline, not override) and written whole by Save. Guard-sources
post-install.sh. (No suite ripple: the baseline object only surfaces where the
operator hasn't overridden.)

**Menu model** (`menu.sh`): the two bool field rows → six structured rows —
Security: firewall (firewalld) / antivirus / rootkit / apparmor; Backup: zfs
snapshots / borg — pathing to `post_install.{security,backup}.*`. The category ●
aggregation is unchanged (folds the per-field override flag).

**Editors** (`guided.sh`): `_guided_edit_firewall` — a single-choice radiolist
(firewalld | ufw | none); picking one IS the mutual exclusion. `_guided_edit_
{antivirus,rootkit,apparmor,zfs_snapshot,borg}` reuse `_guided_edit_bool` over
the structured leaves. The old `_guided_edit_backup`/`_guided_edit_security`
bool editors are gone; the category-loop dispatch + replay branch rewired to the
six new edits. Replay now emits the structured object (overrides merge over the
secure baseline — verified: `firewall=ufw` / `antivirus=false` / `borg=false`
→ those flip, rootkit/apparmor/zfs_auto_snapshot stay true).

**M5 no-user guard**: pure `post_install_guard_users <pi_json> <count>`
(post-install.sh) → aborts when the selection resolves to programs but
`count==0`, with the actionable message. `_guided_guard_post_install` (guided
glue) reads effective `.post_install` + `.users | length` and defers to it;
`guided_build` calls it once, ahead of all three terminal actions (Proceed /
Save / Export). Note: the seed always provides `aquastias`, so the guard is
mostly defensive — tested at the glue level (zero users + selection → abort;
user present → pass; empty selection → pass) plus the pure fn.

Tests: guided-seed(+1), guided-menu (2 rewritten to structured rows), guided-
shell (editor + guard + replay tests; the old backup-editor test replaced),
post-install.bats (+3 guard). Full suite **1288 bats, 0 failures; shellcheck
clean** (--severity=warning).

**VM smoke DONE (2026-06-22) — AC6 satisfied.** `vm.sh --guided --profile
single/guided-extras --verify-boot`: the guided replay drove the Security &
Backup categories (re-picked `vm-test` as the minimal `users[0]`; toggled the
Backup category off — borg/zfs_snapshot=false), installed **EXIT-0**, and the
first-boot sentinel emitted **`EXTRAS-OK`** — firewalld + clamav + rkhunter +
apparmor all `systemctl is-enabled` on the booted system — then `FIRSTBOOT-OK`.
This exercises the issue-05 seed pre-tick + structured-object emit AND the
issue-04 resolver→Runner paru pass end-to-end. (The fully-on object profile,
incl. borg + SOPS + encryption, also installs to EXIT-0 — see issue 04's
`headless/secure` smoke.) Harness: new `verify_extras`/`guided_extras` seed-
generator seams + the `single/guided-extras` profile.

**The VM smoke flushed a latent guided-installer bug (fixed):** the redesign's
replay path (`guided_build`) `return 1`'d on an absent answer, which aborted
under install.sh's `set -Eeuo pipefail` — so *every* headless guided install was
broken (bats never caught it: no `set -e`, and no guided VM smoke had run since
the redesign). Fixed by suspending errexit + the inherited ERR trap across the
best-effort replay edits, with a regression test. Commits `32b4967` + `099e89b`.

**The redesign v2 issues (02-05) are all done, VM-verified.**
