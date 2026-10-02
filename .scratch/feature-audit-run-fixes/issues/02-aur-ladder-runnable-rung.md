# 02: AUR ladder: runnable rung + low-mem source build

**What to build:** The AUR Helper bootstrap accepts a rung only if the helper
runs; rung 1 (paru from source) builds within 4G (LTO off, limited jobs,
bootstrap only). Minimal Profile installs. Fixes F002 (minimal: paru-bin vs
libalpm.so.15). Amends ADR 0052.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] profiles-bootstrap.bats: non-running helper drops to next rung
- [ ] profiles-bootstrap.bats: bootstrap build env set for rung 1
- [ ] ADR 0052 amended
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (minimal)

## Comments

Rung counts only if the helper runs; lean source build (f84a402); ADR 0052
amended. Live run: minimal landed source paru.
