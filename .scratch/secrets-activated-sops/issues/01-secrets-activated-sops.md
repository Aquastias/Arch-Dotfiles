Status: ready-for-agent

# Secrets-activated sops Program

## Parent

`.scratch/secrets-activated-sops/PRD.md` (ADR 0025).

## What to build

Remove the sops Program from Host Core's `system_programs`. The
Runner installs sops only when the host or one of its declared users
ships a `secrets.json` — detected from install-state (`.secrets.host`
set, or `.secrets.users` non-empty) via a pure predicate — selecting
sops through the normal System Program install path, deduplicated
against any declared programs. `go` and the SOPS Runtime Service then
land only on hosts that actually use secrets; hosts with none get
neither.

The sops Program itself is unchanged: it still builds `ssh-to-age`
via `go` and leaves `go` installed afterwards. sops becomes the one
System Program whose selection is implicit — the documented
exception already recorded in `CONTEXT.md`.

## Acceptance criteria

- [ ] Host Core `system_programs` no longer lists `sops`.
- [ ] A pure predicate returns true iff install-state `.secrets.host`
      is set or `.secrets.users` is non-empty; bats covers empty →
      false, host-secret → true, user-secret → true.
- [ ] When secrets are present, the Runner installs the sops Program
      via the normal system-program path, deduplicated against
      declared programs.
- [ ] When no secrets are present, sops is not installed and `go` is
      never pulled in.
- [ ] `programs/security/sops/install.sh` is unchanged; `go` remains
      after building `ssh-to-age`.
- [ ] No System Program other than sops gains implicit activation;
      the `CONTEXT.md` exception holds.

## Blocked by

- None - can start immediately.
