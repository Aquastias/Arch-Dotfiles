# Foundations: GPU vendors in install-state + drop envycontrol

Status: done

## Parent

`.scratch/hybrid-gpu-hardening/PRD.md` — Hybrid AMD+NVIDIA GPU hardening
(ADR 0053).

## What to build

The seam the GPU Hardening feature stands on, landed so **nothing changes about
graphics at runtime yet** (expand step). Two independent, low-risk changes:

1. **GPU vendors reach the chroot.** `install-state.json` gains a `gpu` array,
   written from the resolved `ENVIRONMENT_GPU`, and loadable by chroot modules
   through the existing install-state load path. Preserves both shapes — the
   single-vendor case (e.g. `nvidia`) and the array case (`[amd, nvidia]`) —
   losslessly. No chroot module consumes it yet.
2. **Drop `envycontrol`.** GPU Resolution no longer adds `envycontrol` to the
   paru set for an `amd`+`nvidia` result. The package was installed but never
   invoked, so removing it is functionally inert today; it clears the way for
   the version-controlled hardening config to be the single source of truth
   (ADR 0053).

Update the **GPU Resolution** entry in `CONTEXT.md`: an `amd`+`nvidia` result no
longer installs `envycontrol`.

## Acceptance criteria

- [ ] `install-state.json` carries a `gpu` array populated from
      `ENVIRONMENT_GPU`; a chroot module can read it back.
- [ ] Round-trip is lossless for both the array (`[amd,nvidia]`) and
      single-vendor shapes (bats test).
- [ ] Resolving `[amd,nvidia]` yields a `GPU_PARU_PACKAGES` with **no**
      `envycontrol` (bats regression test).
- [ ] `CONTEXT.md` GPU Resolution entry reflects the envycontrol removal.
- [ ] Existing environment-resolution and install-state tests still pass; no
      change to single-vendor / VM installs.

## Blocked by

None - can start immediately.
