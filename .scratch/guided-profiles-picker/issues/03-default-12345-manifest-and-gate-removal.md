# Default-`12345` posture: manifest + Proceed-gate removal

Status: ready-for-agent

## Parent

.scratch/guided-profiles-picker/PRD.md
ADR: docs/adr/0055-guided-profiles-picker-and-default-secret-posture.md

## What to build

The core of the secret-posture flip (global, every guided install). Root,
per-user passwords, and the encryption passphrase **default to `12345`**, and
**Proceed is no longer gated** on any secret. The existing "required-but-unset"
gate signals become **display-only**, not blockers, so Proceed is always
available. The no-SOPS secrets manifest builder fills any unset secret with
`12345` before install-state staging, so the back-end always receives a concrete
value. The `12345` default is runtime-only and never enters Config State, Save,
or Export (secret-free-state invariant of ADR 0042/0051 unchanged). This
supersedes the ADR 0051/0054 Proceed password/passphrase gate.

## Acceptance criteria

- [ ] Proceed is never blocked on a missing root/user password or encryption
      passphrase
- [ ] The menu no longer emits a Proceed-block signal for unset secrets (the
      former `_ctl_pw_missing` / `_ctl_enc_missing` blockers are display-only)
- [ ] The secrets manifest emits `12345` for any secret left unset
- [ ] A set (operator-typed) secret emits its own value, not `12345`
- [ ] No secret value (default or typed) appears in the emitted Config State,
      Save, or Export
- [ ] The `WILL ERASE` / typed-`INSTALL` consent gate still runs on every Proceed
- [ ] bats over the manifest builder (`guided-secrets.bats` prior art) and the
      menu gate signal (`guided-menu.bats` prior art)

## Blocked by

- None — can start immediately (parallel to 01).
