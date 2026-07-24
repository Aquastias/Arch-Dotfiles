# Resilient AUR-helper bootstrap ladder

Status: done

Decision of record: **ADR 0052** (resilient AUR-helper bootstrap ladder),
building on ADR 0041 (host Security/Backup Extras via the Primary User's paru
pass) and ADR 0036 (unified profile / Effective Config). Test tiers per ADR
0046 / 0048 (two-tier combination matrix + realism tiers).

Glossary touched (`CONTEXT.md`): **AUR Helper** (new — the resolved helper,
default paru, threaded via `$AUR_HELPER`); generalizes the existing **User
Program** and paru-pass entries from the literal "paru" to "the AUR Helper".

## Problem Statement

The installer aborts completely when the single AUR-helper bootstrap path fails.
`_profiles_bootstrap_paru` runs exactly one sequence per user — `git clone
aur/paru.git && makepkg -si` — and `makepkg` fetching paru's **source tarball**
from GitHub codeload returned a 504. A transient upstream hiccup on one endpoint
therefore kills an otherwise-fine install, with no second attempt and no
alternative. The operator's whole run is lost to a problem that would have
cleared on a retry or via a different download endpoint.

## Solution

The bootstrap becomes a **resilience ladder** that tries multiple ways to get a
working AUR helper before giving up. It first retries `paru` from source
(shallowly), then falls back to `paru-bin` and finally `yay-bin` — both prebuilt
from GitHub **Releases**, a different endpoint than the codeload that 504s, so a
codeload outage no longer means total failure. The first rung to yield a working
helper wins; only exhausting all three aborts, and it still aborts cleanly.

The goal is *resilience — get some helper working* — not "add yay as a feature":
yay built from source hits the same codeload as paru, so only its `-bin` variant
earns a rung. Because a rung may land a binary named `yay` instead of `paru`, the
winning helper's identity is threaded through a new `$AUR_HELPER` seam so every
downstream install call uses whatever landed. From the operator's seat, a flaky
GitHub the day they reinstall no longer costs them the install.

## User Stories

1. As an operator reinstalling during a transient GitHub codeload 504, I want
   the paru source build retried a couple of times, so that a momentary blip
   doesn't abort my install.
2. As an operator whose codeload stays down, I want the bootstrap to fall back
   to `paru-bin` from GitHub Releases, so that a different endpoint gets me a
   working helper.
3. As an operator whose paru path is fully unavailable, I want a final `yay-bin`
   fallback, so that a different upstream project can still provide an AUR
   helper.
4. As an operator, I want the ladder to try the *fastest independent path*
   quickly rather than hammer one dead endpoint, so that my install proceeds in
   ~40s worst case instead of minutes.
5. As an operator, I want `paru` from source tried first, so that when upstream
   is healthy I get the self-compiled helper I get today — behaviour is
   unchanged on the happy path.
6. As an operator, I want a `-bin` fallback to skip the `rust`/`cargo` compile,
   so that a fallback install is also lighter and faster.
7. As an operator, I want the fallback binaries checksum-verified by makepkg
   (sha256 pinned in the PKGBUILD), so that resilience doesn't cost me
   integrity.
8. As an operator, I want the install to still abort cleanly when *all* rungs
   fail, so that a genuine total outage is reported, not silently half-done.
9. As a maintainer, I want the winning helper's name resolved into a single
   `$AUR_HELPER` value, so that downstream install calls don't care which rung
   won.
10. As a maintainer, I want the Runner to export `$AUR_HELPER` alongside
    `OS_DIR` / `PROGRAMS` / `SHELL_COMMONS`, so that program scripts read it the
    same way they read every other injected value.
11. As a program-script author (`programs/*/install.sh`), I want to call
    `${AUR_HELPER} -S` instead of literal `paru`, so that my script works
    whichever helper the ladder landed.
12. As an operator running the standalone `install-pkglist.sh` on a booted
    system, I want it to detect `paru` or `yay` automatically, so that it keeps
    working on a system where the ladder landed yay.
13. As an operator with no AUR helper installed at all, I want
    `install-pkglist.sh` to die with a clear message, so that I'm not left
    guessing why nothing installed.
14. As the Primary User's AUR pass, I want the pre-flight conflict report to run
    only under paru, so that I'm not shown a half-parsed pass whose output can't
    be interpreted under yay.
15. As an operator on the rare yay fallback path hitting a provider conflict, I
    want the real install to surface the failure via the normal ERR trap, so
    that correctness is preserved even though the pretty pre-download hint is
    absent.
16. As a maintainer, I want the helper resolution to be **per user**, so that a
    blip leaving one user on paru and another on yay is harmless with no
    cross-user state to keep coherent.
17. As a maintainer, I want the retry/ladder decision logic extracted to pure,
    stubbable functions, so that I can test rung ordering and helper resolution
    without ever running paru or a chroot.
18. As a future reader of the code, I want the ubiquitous term generalized from
    "paru" to "AUR Helper (default paru)" in `CONTEXT.md`, so that the ladder and
    the `$AUR_HELPER` seam are documented where the vocabulary lives.
19. As a maintainer, I want `_profiles_detect_helper` shared by the Runner and
    `install-pkglist.sh`, so that helper resolution has exactly one definition.
20. As an operator, I want each rung's retry to fail fast (2 attempts, 3s/10s
    backoff) then drop to the next endpoint, so that the cross-endpoint ladder —
    not per-rung persistence — does the resilience work.

## Implementation Decisions

- **Ladder in `_profiles_bootstrap_helper`** (renamed from
  `_profiles_bootstrap_paru`). Rungs, in order: (1) `paru` source
  (`git clone aur/paru.git && makepkg -si`), (2) `paru-bin`, (3) `yay-bin`. Rungs
  2 and 3 install checksum-pinned prebuilt binaries from GitHub Releases. First
  rung yielding a working helper wins; break on success.
- **Skip-check** at the top of the bootstrap: `command -v paru || command -v yay`
  — a user who already has either helper is not rebuilt.
- **Rung executor is a seam.** Each rung is a parameterized executor
  (`_bootstrap_rung <aur-pkg>`) doing the `git clone + makepkg` in `arch-chroot`.
  The ladder orchestrates `for pkg in paru paru-bin yay-bin`; the executor is
  stubbable so ladder ordering / break-on-success / all-fail-abort are testable
  without I/O.
- **Retry wrapper `_retry <attempts> <backoff-csv> -- cmd…`**, generic. Applied
  per rung with **2 attempts, backoff `3,10` (seconds)**. `rm -rf $BUILD` between
  attempts. `sleep` is injectable so tests run instantly. Worst-case total across
  the ladder ~40s before abort.
- **`_profiles_detect_helper`** (pure) resolves the landed helper name:
  `command -v paru || command -v yay`, else non-zero. This value is the
  `$AUR_HELPER`. Shared by the Runner and `install-pkglist.sh` — one definition,
  two callers.
- **`$AUR_HELPER` injection.** The Runner exports `AUR_HELPER` alongside the
  existing `OS_DIR` / `PROGRAMS` / `SHELL_COMMONS` env injection into program
  scripts. Resolution is **per user** (each user's programs run under that user's
  landed helper).
- **Runner AUR pass (`_profiles_aur_install`).** `paru -Sp` / `paru -S` become
  `${AUR_HELPER} …`. The pre-flight pass plus `_profiles_aur_conflict_report`
  are **gated to `helper == paru`**; under yay the pre-flight is skipped and the
  install goes straight to the real pass (ERR trap surfaces any conflict).
- **11 `programs/*/install.sh`.** Mechanical `paru` → `${AUR_HELPER}` in each
  `-S` invocation (firewalld, apparmor, clamav, rkhunter, ufw, teamspeak3,
  docker, virt-manager, podman, zfs-auto-snapshot, borg, and the remaining
  Security/Backup/Virtualization/Communication scripts).
- **`install-pkglist.sh`** (standalone, outside the env seam) uses
  `_profiles_detect_helper` (or an inlined equivalent if it can't source the
  Runner) to pick `paru`/`yay`, dies with a clear message if neither exists, and
  runs `<helper> -S --needed - < list`.
- **Docs.** `CONTEXT.md` gains an **AUR Helper** entry and generalizes the User
  Program / paru-pass wording; ADR 0052 records the decision.

## Testing Decisions

Good tests here assert **external behaviour of the pure decision core** — which
helper resolves, how many attempts ran, whether an exhausted ladder aborts —
never the internals of `git clone` / `makepkg`, which are I/O and stay untested
at unit level. Prior art: `.os/tests/profiles/profiles-aur.bats` sources
`runner.sh` directly, `run`s the pure function, and asserts on stdout/status
with paru never executing. New tests follow that shape.

- **`_profiles_detect_helper`** — bats: stub PATH so only `paru`, only `yay`,
  both, or neither is present; assert the resolved name and the die-if-neither
  branch. This is the seam reused by `install-pkglist.sh`.
- **`_retry`** — bats: a fake command that fails N times then succeeds; inject a
  no-op `sleep`; assert attempt count, final status, and that backoff values are
  consumed in order. Cover exhausted-attempts → non-zero.
- **Ladder orchestration** — bats: stub `_bootstrap_rung` to succeed on a chosen
  rung; assert (a) rung-1 success → `paru`, (b) rungs 1–2 fail, `paru-bin`
  succeeds → `paru`, (c) rungs 1–2 fail, `yay-bin` succeeds → `yay`, (d) all fail
  → abort non-zero. Also assert the pre-flight gate: `helper == paru` runs
  pre-flight, `helper == yay` skips it.
- **`install-pkglist.sh`** — bats or a focused harness: stub PATH, assert helper
  selection and the die-if-neither path.
- **Happy-path integration** — the existing VM / combination-matrix tier (ADR
  0046 / 0048) already exercises rung 1 end-to-end on a real install; no new VM
  case is added, since forcing a fallback rung would require simulating an
  upstream outage.

## Out of Scope

- Simulating an upstream 504 in the VM/matrix tier to force fallback rungs.
- Teaching `_profiles_aur_conflict_report` yay's conflict phrasing — the early
  actionable hint stays a paru-only affordance by design.
- A `paru`-named shim over yay — rejected in ADR 0052 in favour of `$AUR_HELPER`.
- Making the retry counts / backoff operator-configurable — the values are fixed
  constants (2 attempts, 3s/10s).
- Any change to how AUR packages are *resolved* (`_profiles_resolve_aur`) or to
  the host `packages.aur` schema.

## Further Notes

- The 504 was on GitHub **codeload** (the source tarball), not the AUR git repo
  clone (which succeeded) — this is why source `yay` earns no rung but `-bin`
  (Releases endpoint) does.
- `paru-bin` *provides* `paru`, so when rung 2 wins, downstream `${AUR_HELPER}`
  resolves to `paru` with zero further branching.
- Mixed helpers across users on one install run are acceptable and expected
  under a transient blip; each user's scripts use their own `$AUR_HELPER`.
