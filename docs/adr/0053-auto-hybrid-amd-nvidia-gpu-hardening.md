# Auto hybrid AMD+NVIDIA GPU hardening; drop envycontrol

---
Status: accepted
---

When GPU Resolution detects **both** `amd` and `nvidia` (the `auto` path on a
switchable-graphics laptop such as a Legion 5: AMD iGPU + NVIDIA RTX 3060 dGPU),
the installer now applies a **deterministic hybrid-graphics hardening set** in
the chroot rather than merely installing drivers. Previously the only hybrid-
specific action was pulling `envycontrol` into the paru set — a runtime mode
switcher the installer **never invoked** — while nothing set `nvidia-drm.modeset`,
loaded the NVIDIA stack early, or rebuilt the initramfs on driver upgrade. That
left the exact race the hardening now closes: at boot `amdgpu` and `nvidia_drm`
both register DRM devices, and the window where the dGPU is half-initialised (or
modeset is off) is precisely when PRIME offload and suspend/resume break —
intermittently, so it presents as a race. KDE reaches a usable Wayland login
with the compositor on the reliable AMD iGPU and the NVIDIA dGPU idle until
offloaded.

The hardening is **auto-gated on `amd`+`nvidia` both present** in the resolved
GPU vendor list — no new config field. The target is zero-config correctness for
the laptop case; a desktop that happens to pair both vendors gets a harmless
superset (modeset and `PreserveVideoMemoryAllocations` are safe; the
suspend/resume services are effectively no-ops off-battery). Because the chroot
cannot currently see the resolved vendors (`install-state.json` carries no GPU
field), a **`gpu` array is threaded into install-state**, and a new chroot
module **`lib/chroot/gpu.sh`** consumes it. It runs **before `initcpio.sh`** so
the single `mkinitcpio -P` bakes in both the early-KMS `MODULES` and the
`modprobe.d` options — no second initramfs build.

The hardening set, all owned by `gpu.sh`:

- `/etc/modprobe.d/nvidia.conf` — `options nvidia_drm modeset=1 fbdev=1`,
  `options nvidia NVreg_PreserveVideoMemoryAllocations=1`,
  `options nvidia NVreg_DynamicPowerManagement=0x02`, `blacklist nouveau`.
- Early KMS — `nvidia nvidia_modeset nvidia_uvm nvidia_drm` appended to
  `MODULES=` in `/etc/mkinitcpio.conf` (initcpio.sh today sets only `HOOKS`).
- RTD3 — a udev rule setting the dGPU PCI `power/control=auto` so the idle dGPU
  reaches D3cold (fine-grained runtime power management).
- Enable `nvidia-suspend` / `nvidia-resume` / `nvidia-hibernate`.
- A pacman hook (named to sort **after** the `dkms` hook, e.g.
  `95-nvidia-initramfs.hook`) that rebuilds the initramfs on any
  `nvidia`/`linux*` upgrade, so modeset+early-KMS survive kernel/driver bumps.

`nvidia-open-dkms` builds cleanly during pacstrap because matching
`*-headers` are already in the pacstrap set for every selected kernel; the RTX
3060 (Ampere) is fully supported by the open kernel module.

## Considered Options

### Runtime topology
- **Hybrid / PRIME offload** — chosen. Matches the firmware's switchable-
  graphics mode; the compositor runs on the robust AMD iGPU and never touches
  NVIDIA, so the greeter/login path has no dependency on the proprietary stack.
- **dGPU-only / iGPU-only** — rejected as the default. dGPU-only means worst
  battery and firmware-dependent output routing on a switchable-graphics box;
  iGPU-only forfeits CUDA/discrete performance. Both remain reachable later by a
  deliberate reconfig, not a default.

### Mechanism: hand-rolled config vs envycontrol
- **Hand-rolled config, drop `envycontrol`** — chosen. The version-controlled
  `modprobe.d` + `MODULES` + udev + hook set is the single source of truth. Two
  tools owning the same files is the drift trap this repo avoids, and
  `envycontrol` does not by itself add early-KMS `MODULES` or the initramfs
  regen hook — so keeping it would leave partial, split ownership.
- **Invoke `envycontrol -s hybrid --rtd3`** — rejected. Still needs the early-
  KMS + hook patch on top, giving murkier ownership than owning the whole set.
- **Keep it installed but uninvoked** — rejected. That is the pre-existing state
  whose only effect is a switcher that can silently overwrite our files.

### modeset location: modprobe.d vs kernel cmdline
- **`modprobe.d`** — chosen. Self-contained in `gpu.sh`; mkinitcpio bakes
  `modprobe.d` into the initramfs so early-KMS load honours it. Zero bootloader
  changes; identical for systemd-boot and GRUB.
- **Kernel cmdline** — rejected. Would thread a param through both Bootloader
  Adapters and the `ROOT_CMDLINE` seam — two code paths to keep in sync for no
  functional gain.

### dGPU power: RTD3 vs always-on
- **RTD3 runtime PM (D3cold when idle)** — chosen. Large battery win on Ampere,
  solid with `nvidia-open` on recent kernels; accepted a tiny first-offload
  wake-latency risk.
- **Always powered** — rejected as default. Rock-solid but several watts of
  constant idle drain on a laptop.

### Gating: auto-detect vs explicit mode knob
- **Auto when `amd`+`nvidia` detected** — chosen. Zero new schema surface for a
  decision already fixed to hybrid; matches the "no problems on login" target.
- **`environment.gpu_mode` field** — rejected for now. Real new surface (schema,
  accessors, guided menu, validation, docs) that future-proofs iGPU/dGPU-only
  but buys nothing for the committed hybrid case.

## Consequences

- The chroot gains a GPU-vendor input it never had; `install-state.json` grows a
  `gpu` array and `gpu.sh` joins the chroot module sequence ahead of
  `initcpio.sh`. Ordering is load-bearing — reordering after the
  `mkinitcpio -P` would silently drop early KMS.
- SDDM stays **Wayland-only** with the existing `plasma-x11-session` fallback
  (ADR/commit `plasma-x11-session`): the compositor on amdgpu makes Wayland the
  safe primary, and X11 remains the black-screen escape hatch.
- **Not VM-verifiable.** No VM emulates the proprietary NVIDIA stack or hybrid
  hardware, so the Combination Matrix can only prove "installs without error."
  Correctness is covered by bats unit tests over the pure generators (gating +
  exact `modprobe.d`/`MODULES`/udev/hook text) plus a manual on-hardware
  checklist: `nvidia_drm/parameters/modeset` = `Y`, `prime-run glxinfo` reports
  the NVIDIA renderer, the idle dGPU reaches D3cold, and suspend/resume returns
  without a black screen.
- Dropping `envycontrol` removes the one-command runtime switch to
  integrated-only / dGPU-only; changing topology is now a deliberate reconfig.
