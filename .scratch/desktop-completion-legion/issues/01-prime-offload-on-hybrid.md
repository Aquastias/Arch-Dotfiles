# 01: PRIME offload on hybrid machines

**What to build:** on an amd+nvidia install, GPU Hardening installs
`nvidia-prime`, so `prime-run <app>` runs the app on the dGPU. Single-vendor,
VM and intel installs are unchanged. Parent: PRD (ADR 0161).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] amd+nvidia: `nvidia-prime` is installed by GPU Hardening.
- [x] Single-vendor NVIDIA, AMD, intel and VM: `nvidia-prime` absent.
- [x] GPU Hardening gate tests cover both outcomes.
- [x] Arch Wiki (PRIME) fetched and cited in the comment.

## Comments

- 2026-11-02 (review): `nvidia-prime` is installed via GPU Resolution's
  hybrid package set (`gpu_hybrid_packages`, the shared pure GPU map), not
  by GPU Hardening — Hardening writes config and runs no pacman, and the map
  lets the Package Resolver report it. Tests: `gpu-resolution.bats`,
  `derivation.bats`, `resolver-derived-sets.bats`. ADR 0161 amended.
