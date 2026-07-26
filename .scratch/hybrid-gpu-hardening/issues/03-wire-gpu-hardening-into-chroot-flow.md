# Wire GPU Hardening into the chroot flow

Status: ready-for-agent

## Parent

`.scratch/hybrid-gpu-hardening/PRD.md` — Hybrid AMD+NVIDIA GPU hardening
(ADR 0053).

## What to build

The enable step: the GPU Configuration Module goes live. `configure.sh` invokes
`gpu.sh` **before** `initcpio.sh`, so on an `amd`+`nvidia` install the whole
hardening set lands and the single `mkinitcpio -P` bakes in both the Early-KMS
MODULES and the `modprobe.d` options — no second initramfs build. Ordering is
load-bearing: running after the build would silently drop Early KMS.

On the gate passing (both vendors present, read from the install-state `gpu`
array), the module writes the modprobe config, augments the MODULES line,
installs the udev RTD3 rule and the initramfs-regen pacman hook, and enables the
NVIDIA suspend/resume/hibernate services. When the gate does not pass
(single-vendor, VM, intel), the module is a no-op and the install is byte-for-
byte unchanged.

Land the remaining glossary + docs:

- New `CONTEXT.md` terms: **Hybrid Graphics** / **PRIME Offload**, **GPU
  Hardening**, **Early KMS**, **RTD3**.
- The manual on-Legion acceptance checklist (from the PRD's Further Notes)
  recorded alongside the feature so on-hardware verification is repeatable.

SDDM stays Wayland-only with the existing `plasma-x11-session` fallback — no
display-manager change in this slice.

## Acceptance criteria

- [ ] `gpu.sh` runs from `configure.sh` strictly before `initcpio.sh`.
- [ ] On an `amd`+`nvidia` effective config, all artifacts exist before
      `mkinitcpio -P`: modprobe conf present, MODULES line contains the four
      nvidia modules, udev rule + pacman hook installed, suspend/resume/hibernate
      services enabled.
- [ ] On a single-vendor / VM config the module is a no-op — no GPU artifacts
      written, install output unchanged.
- [ ] `CONTEXT.md` gains the Hybrid Graphics / GPU Hardening / Early KMS / RTD3
      terms.
- [ ] The manual on-Legion checklist is recorded (modeset=Y, prime-run → NVIDIA
      renderer, idle dGPU D3cold, clean suspend/resume, regen hook survives a
      driver/kernel upgrade).
- [ ] An install-only run (e.g. a matrix cell / VM) still completes without
      error — the module never aborts a non-hybrid install.

## Blocked by

- `.scratch/hybrid-gpu-hardening/issues/01-foundations-gpu-install-state-drop-envycontrol.md`
- `.scratch/hybrid-gpu-hardening/issues/02-gpu-configuration-module-pure-core.md`
