# 02: Dynamic Boost on hybrid machines

**What to build:** on an amd+nvidia install, GPU Hardening enables
`nvidia-powerd`, so the RTX 3060 gets its Dynamic Boost budget. No other
GPU set enables it. Parent: PRD (ADR 0161).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] amd+nvidia: `nvidia-powerd.service` enabled beside the existing
      suspend/resume/hibernate services.
- [x] Single-vendor and VM: not enabled.
- [x] GPU Hardening gate tests cover both outcomes.
- [x] Arch Wiki (NVIDIA, Dynamic Boost) fetched and cited, including the
      firmware / Performance mode caveat.
