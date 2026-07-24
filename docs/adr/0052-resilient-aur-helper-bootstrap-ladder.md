# Resilient AUR-helper bootstrap ladder

---
Status: accepted
---

The per-user AUR-helper bootstrap no longer aborts the install on a transient
upstream failure. Previously `_profiles_bootstrap_paru` ran exactly one path —
`git clone aur/paru.git && makepkg -si` — and a 504 from GitHub **codeload**
(makepkg fetching paru's source tarball) killed the whole install. It is now a
**resilience ladder** that tries, in order: (1) `paru` from source, (2)
`paru-bin`, (3) `yay-bin` — the first to yield a working helper wins, and only
exhausting all three aborts. The point is *resilience, get some helper working*,
not yay-as-a-feature: yay built from source hits the **same codeload** that
504s, so it earns no rung; the independent path comes from the `-bin` packages,
whose PKGBUILD `source=` pulls a checksum-pinned prebuilt binary from GitHub
**Releases** — a different endpoint than codeload — and skips the `rust`/`cargo`
compile entirely.

Because a rung may land a binary named `yay` rather than `paru`, the winning
helper's identity is threaded through a new **`$AUR_HELPER`** seam. The Profiles
Runner exports it alongside the existing `OS_DIR` / `PROGRAMS` / `SHELL_COMMONS`
injection, and every downstream `paru -S` — the Runner's own AUR pass plus the
11 `programs/*/install.sh` scripts — reads `${AUR_HELPER}` instead of the
literal. The ubiquitous term in `CONTEXT.md` shifts accordingly from **paru** to
**AUR Helper (default paru)**. Resolution is **per user**: each user's programs
run under whatever helper that user's bootstrap landed, so a transient blip that
leaves user A on `paru` and user B on `yay` is harmless — no cross-user state to
keep coherent.

Retry is **shallow — an initial try plus 2 retries per rung, 3s/10s backoff**,
then drop to the next rung. Deep per-rung retry would be wrong here: since the
next rung is a *different endpoint*, hammering a dead codeload for a minute is
wasted when `paru-bin` would succeed immediately; the cross-endpoint ladder is
the resilience lever, not per-rung persistence. Worst-case total is ~40s before
abort.

The AUR pre-flight (`_profiles_aur_install`, `paru -Sp` + conflict-report grep)
is **gated to `helper==paru`**. Under yay it is skipped entirely rather than run
half-parsed: yay supports `-Sp` but phrases conflicts differently, so the grep
would silently miss and the actionable early hint would be lost anyway — running
an analysis whose output can't be interpreted is worse than not running it. On
the rare yay path a provider conflict therefore surfaces via the real install's
ERR trap, without the pretty pre-download report.

## Considered Options

### What earns a rung
- **`paru` source → `paru-bin` → `yay-bin`** — chosen. Source first keeps
  today's behaviour and a self-compiled binary; the two `-bin` rungs add a
  genuinely independent endpoint (Releases, checksum-verified).
- **Add `yay` from source** — rejected. Same codeload host as paru; buys no
  independent download path against the failure we actually hit.
- **`-bin`-only / source-only** — rejected. Source-only collapses the ladder to
  two same-endpoint rungs; `-bin`-only discards the self-compiled path with no
  resilience gain over having it as rung 1.

### Keeping the downstream `paru` calls alive
- **`$AUR_HELPER` env var** — chosen. Explicit, reuses the Runner's existing
  env-injection seam, glossary-worthy. Costs a mechanical `paru` →
  `${AUR_HELPER}` sweep across the 11 program `install.sh` scripts.
- **A `paru`-named shim over yay** — rejected. Zero downstream edits, but a
  `paru` on PATH that is secretly yay is exactly the surprising-without-context
  trap this repo avoids, and yay's differing `-Sp` output would make the shim
  misbehave under the pre-flight.

## Consequences

- `install-pkglist.sh` (a standalone post-install tool, outside the Runner's env
  seam) auto-detects `command -v paru || command -v yay` and dies if neither, so
  it keeps working on a system where the ladder landed yay.
- `_profiles_aur_conflict_report` stays paru-tuned by design; its early
  actionable hint is a paru-only affordance. Documented, not a regression —
  correctness on yay is unchanged, only the pre-download nicety is absent.
- The abort contract is preserved: a total AUR/GitHub outage still fails the
  install cleanly, just after ~40s of laddered attempts instead of one shot.
