# Aquamarine DRM pinning on hybrid GPU

Status: ready-for-agent

## Parent

`.scratch/hyprland-readd/PRD.md` (ADR 0062, 0053)

## What to build

On a hybrid AMD+NVIDIA machine, a Hyprland install pins the compositor to the
integrated GPU so aquamarine does not grab the NVIDIA node and black-screen. The
Hyprland adapter writes a udev rule minting a stable, colon-free integrated-GPU
DRM symlink plus an `AQ_DRM_DEVICES` entry in the system login environment, gated
on the resolved `amd`+`nvidia` set read from install-state's `gpu` array
(ADR 0053's seam). Because the pin lands in the system login environment it
reaches every session type (SDDM and tuigreet) with no per-DM handling. On
non-hybrid hardware nothing is written.

## Acceptance criteria

- [ ] Resolved GPU set is `amd`+`nvidia` → udev rule + `AQ_DRM_DEVICES` login-env
      pin written
- [ ] Single-vendor GPU → neither is written
- [ ] The pin lands in the system login environment (reaches SDDM and tuigreet)
- [ ] Gate reads the `gpu` array from install-state (no new config key)
- [ ] `hyprland-adapter.bats` covers hybrid-writes and non-hybrid-no-op and is green

## Blocked by

- Hyprland-only install, end-to-end
