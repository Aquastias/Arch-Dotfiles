# Guided Installer captures credentials in the menu, not after it

The Guided Installer collects the root and per-user passwords **inside** the
persistent fzf, not in a post-menu prompt. A masked, confirmed prompt runs under
an fzf `execute()` (which has a tty); because that subprocess cannot write the
parent shell's variables, the captured secret is handed back through a dedicated
tmpfs file (`GUIDED_SECRETS_FILE`, shape
`{ root_password?, users?: { <name>: { password } } }`). The parent loads it
into the existing held-aside vars, so the tested no-SOPS manifest path
(`_guided_secrets_manifest`) is unchanged. Rows show only `(set)` / `(not set)`;
Proceed is gated in-menu (an fzf `transform` that emits a header warning + bell
instead of `accept`) until root and every enabled user has a password.

This **supersedes the post-menu-password portion of ADR 0042** (which collected
passwords at the commit step, after the operator left the menu). Everything else
in ADR 0042 (the single persistent-fzf control model) stands.

Builds on ADR 0042 (persistent-fzf controller), ADR 0025 (implicit SOPS gated on
`.secrets.*`), and ADR 0036 (device-less Effective Config).

## Considered Options

### How the secret reaches Proceed without touching the Config State
- **Dedicated tmpfs handoff file, plaintext** — chosen. The masked prompt runs
  in an execute() subprocess, so a file (not a shell variable) is required to
  return the value. A tmpfs file matches the existing `GUIDED_*_FILE` pattern,
  is RETURN-trap cleaned, and needs no back-end change (the value shape already
  equals the manifest the chroot/Runner consume). The plaintext-in-RAM window is
  identical to what the installer already did (the old held-aside vars, and the
  back-end's own tmpfs `host-secrets.json`).
- **Hash in the menu (mkpasswd/openssl)** — rejected. Removes the plaintext-at-
  rest window but forces the chroot password step and the secrets resolver to
  accept pre-hashed values, a larger blast radius on VM-verified code for a
  negligible gain on a single-user, RAM-only, throwaway live ISO.
- **Store passwords in the Config State** — rejected outright. It would leak
  plaintext into any Save/Export, breaking the ADR 0042 invariant that the
  Config State is secret-free. `GUIDED_SECRETS_FILE` is never referenced by
  emit / Save / Export.

### The unset-credential gate
- **Block Proceed in-menu** — chosen. Deletes the post-menu prompt entirely; a
  missing password shows an inline notice and keeps the operator in the menu (no
  drop-out — the reported annoyance). Root and every enabled user are required;
  `auto`-lock of root was considered and rejected to match current behaviour.
- **Keep the post-menu prompt as a fallback** — rejected; it reintroduces the
  exact drop-out the change set out to remove.

## Consequences

- Replay (scripted answers) is unchanged: it never enters the fzf, so it keeps
  supplying passwords via keyed answers into the held-aside vars.
- Guided stays strictly no-SOPS: `.secrets.*` is untouched, so a committed
  user's `secrets.json` is still ignored in guided mode (every enabled user
  needs an in-menu password).
- The live masked prompt and the in-fzf gate need a real tty/fzf, so they remain
  HITL/VM-verified; all surrounding logic (handoff-file shape, completeness
  predicate, gate directive, manifest round-trip) is bats-covered.
