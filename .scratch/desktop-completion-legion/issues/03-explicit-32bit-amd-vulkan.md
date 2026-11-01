# 03: Explicit 32-bit AMD Vulkan

**What to build:** every AMD host installs `lib32-vulkan-radeon` by design,
so 32-bit Vulkan games see the AMD GPU — on the desktop and on the hybrid
laptop, where `lib32-nvidia-utils` used to satisfy Steam alone. Parent: PRD
(ADR 0161).

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The AMD GPU Resolution set contains `lib32-vulkan-radeon`.
- [ ] With multilib off it is dropped by the existing `lib32-*` filter.
- [ ] amd+nvidia resolves both `lib32-vulkan-radeon` and
      `lib32-nvidia-utils`.
- [ ] GPU Resolution tests cover all three.
