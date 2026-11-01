# 01: PRIME offload on hybrid machines

**What to build:** on an amd+nvidia install, GPU Hardening installs
`nvidia-prime`, so `prime-run <app>` runs the app on the dGPU. Single-vendor,
VM and intel installs are unchanged. Parent: PRD (ADR 0161).

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] amd+nvidia: `nvidia-prime` is installed by GPU Hardening.
- [ ] Single-vendor NVIDIA, AMD, intel and VM: `nvidia-prime` absent.
- [ ] GPU Hardening gate tests cover both outcomes.
- [ ] Arch Wiki (PRIME) fetched and cited in the comment.
