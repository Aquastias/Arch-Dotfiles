# 14: On-Legion checklist + glossary

**What to build:** the operator can verify every hardware-only change on the
Legion the same way each time, and the glossary reflects PRIME offload and
Dynamic Boost. Parent: PRD (ADR 0161).

**Blocked by:** 01, 02, 03, 05, 06.

**Status:** done

- [x] Checklist extended: hybrid BIOS mode required (discrete
      unsupported); `prime-run glxinfo` on NVIDIA; `nvidia-smi -q` Dynamic
      Boost limit; LLL sensors + fan curve; `arc_max` applied; brightness
      keys; battery conservation via Noctalia's plugin; 32-bit Vulkan sees
      the iGPU; niri and Umbriel drive the iGPU.
- [x] `CONTEXT.md` Hybrid Graphics / PRIME Offload entry updated.
- [x] A failed niri/Umbriel iGPU check is noted as a follow-up ticket, not
      fixed here.

## Comments

- 2026-11-02: the merged checklist lives in this feature's PRD
  (§ On-Legion checklist), superseding the hybrid-gpu-hardening list. Running
  it is the operator's, on chronos.
