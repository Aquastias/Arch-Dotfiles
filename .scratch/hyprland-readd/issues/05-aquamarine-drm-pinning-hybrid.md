# Aquamarine DRM pinning on hybrid GPU

Status: done (6719e92)

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

- [x] Resolved GPU set is `amd`+`nvidia` → udev rule + `AQ_DRM_DEVICES` login-env
      pin written
- [x] Single-vendor GPU → neither is written
- [x] The pin lands in the system login environment (reaches SDDM and tuigreet)
- [x] Gate reads the `gpu` array from install-state (no new config key)
- [x] `hyprland-adapter.bats` covers hybrid-writes and non-hybrid-no-op and is green

## Blocked by

- Hyprland-only install, end-to-end

## Comments

- 2026-09-27 audit: 6719e92. Later: seatd took over DRM master (ADR 0068,
  4bfa02c).
