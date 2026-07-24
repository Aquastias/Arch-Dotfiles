# Enable the bootstrap ladder + switch the Runner AUR pass

Status: done

## Parent

`.scratch/aur-helper-ladder/PRD.md` — Resilient AUR-helper bootstrap ladder
(ADR 0052).

## What to build

The capstone: the per-user bootstrap becomes the resilience ladder, and the
Runner's own AUR pass consumes `${AUR_HELPER}`. This is the point at which the
helper can finally resolve to something other than `paru` — safe now because
tickets 02 and 03 already migrated every consumer.

- `_profiles_bootstrap_paru` → `_profiles_bootstrap_helper`. Skip-check
  `command -v paru || command -v yay`. Rungs, in order: (1) `paru` source
  (`git clone aur/paru.git && makepkg -si`), (2) `paru-bin`, (3) `yay-bin` —
  rungs 2 & 3 checksum-pinned prebuilt binaries from GitHub Releases. First rung
  yielding a working helper wins (break on success); exhausting all three aborts
  cleanly.
- Each rung is a **stubbable rung executor** (`_bootstrap_rung <aur-pkg>`) doing
  the `git clone + makepkg` in `arch-chroot`, wrapped in `_retry` (2 attempts,
  backoff `3,10`, `rm -rf $BUILD` between). The ladder orchestrates
  `for pkg in paru paru-bin yay-bin`.
- `_profiles_aur_install`: `paru -Sp` / `paru -S` → `${AUR_HELPER}`. The
  pre-flight pass and `_profiles_aur_conflict_report` are gated to
  `helper == paru`; under `yay` the pre-flight is skipped and the real install
  runs directly (ERR trap surfaces any conflict).

## Acceptance criteria

- [ ] bats (stubbing `_bootstrap_rung`): rung-1 success → resolves `paru`; rungs
      1–2 fail then `paru-bin` succeeds → `paru`; rungs 1–2 fail then `yay-bin`
      succeeds → `yay`; all rungs fail → non-zero abort.
- [ ] bats: pre-flight runs when `AUR_HELPER=paru` and is skipped when
      `AUR_HELPER=yay`; the real install runs in both cases.
- [ ] The rung executor is wrapped in `_retry` with 2 attempts / `3,10` backoff
      and cleans `$BUILD` between attempts.
- [ ] Skip-check short-circuits when either helper is already installed.
- [ ] The existing VM / combination-matrix happy path (rung 1) still installs
      end-to-end; no new VM case is added for fallback rungs.
- [ ] No literal `paru -S` / `paru -Sp` remains in the Runner AUR pass.

## Blocked by

- Ticket 01 (Ladder foundations) — needs `_retry` + `_profiles_detect_helper`.
- Ticket 02 (Migrate program scripts) — all leaf consumers on `${AUR_HELPER}`.
- Ticket 03 (`install-pkglist.sh` detect) — standalone consumer migrated.
