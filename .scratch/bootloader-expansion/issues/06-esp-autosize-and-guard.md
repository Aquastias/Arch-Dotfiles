# 06 — ESP auto-size + pre-install guard

**What to build:** Stop the ESP-overflow brick when many kernels are selected by
sizing the ESP from the Kernel Selection instead of a fixed value. Add an `auto`
mode for `esp_size` that becomes the default and computes, at partition time, an
upward-only estimate: base overhead + per selected kernel (vmlinuz + default
initramfs + fallback initramfs + a ZFS-module surcharge when the root filesystem
is ZFS) + transient sync headroom + one kernel of growth slack, floored at ADR
0038's 2G so it never shrinks below today's default. `grub` is exempt from the
per-kernel term (it reads `/boot` directly and takes a fixed small ESP). Add a
pre-install ESP budget guard — the authoring-time twin of the runtime
PreTransaction preflight — that refuses a numeric `esp_size` pin below the
computed need for an ESP-mirroring loader, with an actionable message naming the
shortfall, surfaced live in the Guided Kernels and Disks screens. A pinned value
is never silently rewritten.

**Blocked by:** 01 — Bootloader Manifest foundation (for the ESP-mirroring vs grub
classification).

**Status:** done

- [x] A pure ESP-budget function computes `need` from the kernel count, root
      filesystem, and loader; a pure auto-size function returns
      `max(2G, roundup(need))`.
- [x] `esp_size: auto` is the default and resolves to a size that holds every
      selected kernel's images; selecting all available kernels with fallbacks on
      a ZFS root yields an ESP large enough to hold them.
- [x] Auto-size is upward-only — it never returns below 2G — and `grub` skips the
      per-kernel term.
- [x] A too-small numeric `esp_size` pin is rejected at profile-load validation
      with an actionable message; the pin is never auto-bumped.
- [x] The same conflict is shown live on the Guided Kernels and Disks screens
      while selecting, not only at Proceed.
- [x] Tests cover the budget across kernel counts and filesystems, the
      upward-only floor, the ZFS surcharge, the grub exemption, and the guard's
      rejection message (prior art: `packages/kernel.bats`,
      `packages/microcode.bats`).

## Comments

- 2026-09-27 doc sync: shipped in 567480d, 201f53b, 363f791, 17f15b0, 9a3224b,
  6019e48, 4f97379 (ADR 0077/0078).
