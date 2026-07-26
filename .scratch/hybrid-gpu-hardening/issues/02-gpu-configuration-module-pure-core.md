# GPU Configuration Module — pure gating + generators

Status: ready-for-agent

## Parent

`.scratch/hybrid-gpu-hardening/PRD.md` — Hybrid AMD+NVIDIA GPU hardening
(ADR 0053).

## What to build

A new **GPU Configuration Module** (`lib/chroot/gpu.sh`), built in the
established pure-core + thin-IO shape of `initcpio.sh` (pure helpers sourced
under a lib-only guard; side effects skipped when the guard is set). This slice
lands the module **fully unit-tested in isolation** but **not yet wired** into
the real install flow (that is slice 03).

Pure core:

- **Gating** — `_gpu_should_harden` over a vendor list: true iff the list
  contains **both** `amd` and `nvidia`; false for any single vendor (`[amd]`,
  `[nvidia]`, `[intel]`, `[vm]`) and the empty list.
- **Text generators**, one per artifact, returning content as strings:
  - modprobe config: `options nvidia_drm modeset=1 fbdev=1`,
    `options nvidia NVreg_PreserveVideoMemoryAllocations=1`,
    `options nvidia NVreg_DynamicPowerManagement=0x02`, `blacklist nouveau`.
  - augmented `MODULES=` line: takes the existing MODULES content and returns it
    with `nvidia nvidia_modeset nvidia_uvm nvidia_drm` appended — **idempotent**
    (re-running does not duplicate entries).
  - RTD3 udev rule: dGPU PCI `power/control=auto` on idle (→ D3cold).
  - initramfs-regen pacman hook: fires on `nvidia*`/`linux*` upgrade, named to
    sort **after** the DKMS hook so the module is built before the image is
    regenerated.

Thin IO layer (present, but only exercised once slice 03 invokes it): write the
files, edit `/etc/mkinitcpio.conf`'s MODULES line, install the pacman hook, and
enable `nvidia-suspend` / `nvidia-resume` / `nvidia-hibernate`.

## Acceptance criteria

- [ ] `_gpu_should_harden` returns true only for a list containing both amd and
      nvidia; false for `[amd]`, `[nvidia]`, `[intel]`, `[vm]`, and empty (bats).
- [ ] Each generator's exact emitted text is asserted (modprobe conf, MODULES
      line, udev rule, pacman hook).
- [ ] The MODULES-line generator is idempotent: a second application adds no
      duplicate nvidia entries (bats).
- [ ] The module sources cleanly under a lib-only guard with no side effects,
      matching the `initcpio.sh` pattern.
- [ ] Not referenced by `configure.sh` yet — real installs are unchanged.

## Blocked by

None - can start immediately (parallel to slice 01).
