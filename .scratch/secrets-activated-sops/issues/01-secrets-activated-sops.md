Status: done

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

- [x] Host Core `system_programs` no longer lists `sops`.
- [x] A pure predicate returns true iff install-state `.secrets.host`
      is set or `.secrets.users` is non-empty; bats covers empty →
      false, host-secret → true, user-secret → true.
- [x] When secrets are present, the Runner installs the sops Program
      via the normal system-program path, deduplicated against
      declared programs.
- [x] When no secrets are present, sops is not installed and `go` is
      never pulled in.
- [x] `programs/security/sops/install.sh` is unchanged; `go` remains
      after building `ssh-to-age`.
- [x] No System Program other than sops gains implicit activation;
      the `CONTEXT.md` exception holds.

## Blocked by

- None - can start immediately.

## Comments

Done via TDD. Predicate `_profiles_host_uses_secrets` + pure
list-shaper `_profiles_sops_selection` in `lib/profiles.sh`; Runner
selects `sops` implicitly when install-state records secrets, deduped.
Host Core `system_programs` → `["cups"]`. `arch-secure` comment
refreshed; `CONTEXT.md` System Program rule cross-references the sops
exception. 9 new bats in `profiles-secrets.bats`; full suite 666/666;
`sops/install.sh` untouched.
