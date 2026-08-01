# Encryption passphrase: Proceed gate + Disks warning + toggle-off retention

Status: done

## Parent

`.scratch/guided-encryption-passphrase-root-shell/PRD.md` (ADR 0054)

## What to build

In-menu enforcement and lifecycle for the encryption passphrase, so the
requirement is visible up front and the operator can't start an install that
would stall or fail on a missing passphrase — full parity with the root/user
password Proceed gate.

An operator with encryption on but no passphrase set sees the gap on the top menu
(the Disks category row flags it) and on Proceed (blocked), then can drill into
Disks to fix it. Toggling encryption off makes the requirement and its warning
disappear without discarding an already-typed passphrase.

## Acceptance criteria

- [ ] While encryption is on and the passphrase is unset, Proceed emits the
      blocked directive (`set passwords first ⚠`) instead of proceeding.
- [ ] The Disks top-category row shows `⚠ 1 pw needed` under the same condition;
      it clears once the passphrase is set (or encryption is off).
- [ ] The Proceed gate aggregates both origins — Users (root + per-user
      passwords) and Disks (passphrase) — so a block can come from either screen.
- [ ] Toggling encryption off hides the `encryption password` row and removes the
      passphrase from the gate.
- [ ] Toggling encryption off then on again shows `(set)` — the stored passphrase
      is retained, not cleared.
- [ ] `tests/config/guided-controller.bats`: Proceed is blocked and the Disks top
      row shows `⚠ 1 pw needed` when encryption is on and the passphrase is unset;
      both clear when it is set; toggling encryption off clears the gate but a
      subsequent toggle-on still reads `(set)`.

## Blocked by

- Ticket 01 (Encryption passphrase: inline capture → manifest → back-end unlock)
  — needs the row, the `enc` target, and the manifest state to gate on.
