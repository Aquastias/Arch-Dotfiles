# Ladder foundations — `_retry`, `_profiles_detect_helper`, `$AUR_HELPER` export

Status: done

## Parent

`.scratch/aur-helper-ladder/PRD.md` — Resilient AUR-helper bootstrap ladder
(ADR 0052).

## What to build

The seam every later ticket builds on, introduced so **nothing changes at
runtime yet** (expand step). Two pure helpers land with tests, the Runner starts
exporting the resolved helper name (which is still always `paru` today), and the
glossary gains the new term. On a healthy system the install behaves exactly as
before.

- `_retry <attempts> <backoff-csv> -- cmd…` — generic retry wrapper. Runs the
  command, on failure sleeps the next backoff value and retries, up to
  `attempts`. Returns the command's last status. `sleep` is injectable so tests
  run instantly.
- `_profiles_detect_helper` — resolves the landed helper: prints `paru` or `yay`
  from PATH (`command -v paru || command -v yay`), non-zero if neither. This
  value is the `$AUR_HELPER`.
- Runner exports `AUR_HELPER` alongside `OS_DIR` / `PROGRAMS` / `SHELL_COMMONS`,
  resolved per user via `_profiles_detect_helper`. Today only `paru` is ever
  bootstrapped, so it always resolves to `paru` — no behaviour change.
- `CONTEXT.md` gains an **AUR Helper** entry (the resolved helper, default paru,
  threaded via `$AUR_HELPER`).

## Acceptance criteria

- [ ] `_retry` returns success when the command eventually succeeds within the
      attempt budget, and the command's failure status when it never does.
- [ ] `_retry` consumes backoff values in order and calls the injected sleep
      between attempts (assert count + sequence); no sleep after the final
      attempt.
- [ ] `_profiles_detect_helper` prints `paru` when only paru is on PATH, `yay`
      when only yay, `paru` when both (paru preferred), and returns non-zero when
      neither.
- [ ] Runner exports `AUR_HELPER` into the program-script environment; on a
      paru-only system it equals `paru`.
- [ ] New bats file(s) follow the `profiles-aur.bats` shape (source `runner.sh`,
      `run` the pure function, assert stdout/status; no paru/chroot executed).
- [ ] `CONTEXT.md` documents **AUR Helper**; existing suite stays green.

## Blocked by

- None — can start immediately.
