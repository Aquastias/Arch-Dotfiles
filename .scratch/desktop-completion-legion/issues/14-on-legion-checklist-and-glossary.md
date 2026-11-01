# 14: On-Legion checklist + glossary

**What to build:** the operator can verify every hardware-only change on the
Legion the same way each time, and the glossary reflects PRIME offload and
Dynamic Boost. Parent: PRD (ADR 0161).

**Blocked by:** 01, 02, 03, 05, 06.

**Status:** ready-for-agent

- [ ] Checklist extended: hybrid BIOS mode required (discrete
      unsupported); `prime-run glxinfo` on NVIDIA; `nvidia-smi -q` Dynamic
      Boost limit; LLL sensors + fan curve; `arc_max` applied; brightness
      keys; battery conservation via Noctalia's plugin; 32-bit Vulkan sees
      the iGPU; niri and Umbriel drive the iGPU.
- [ ] `CONTEXT.md` Hybrid Graphics / PRIME Offload entry updated.
- [ ] A failed niri/Umbriel iGPU check is noted as a follow-up ticket, not
      fixed here.
