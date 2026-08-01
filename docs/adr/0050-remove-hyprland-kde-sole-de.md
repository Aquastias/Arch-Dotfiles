# ADR 0050: Remove Hyprland; KDE is the sole desktop environment

## Status
Superseded by ADR 0062 (Hyprland re-added 2026-08-02). Originally accepted;
amended ADR 0005 (adapter pattern) and ADR 0021 (adapter owns DE packages).

## Context
The installer shipped two Desktop Environment Adapters — KDE and
Hyprland — selectable via `environment.desktop`. Hyprland carried a
disproportionate maintenance tail: a greetd/greetd-tuigreet display
manager only it used, and an ~80-line nvidia-PRIME hybrid block in
`lib/config/environment.sh` (`AQ_DRM_DEVICES`, a vendor-stable DRM
udev rule, `gpu_is_nvidia_hybrid`, `gpu_write_session_env`) that
existed solely because aquamarine mis-picks the DRM node on hybrid
laptops. KWin negotiates the same iGPU/dGPU handoff itself, so none of
that scaffolding served KDE. Hyprland is no longer used.

## Decision
Remove Hyprland entirely. KDE becomes the only valid
`environment.desktop` value (`_VALID_DESKTOP=(kde)`).

- Delete `extras/desktop/hyprland/`, the three Hyprland VM host dirs,
  and every Hyprland VM/test profile.
- Delete the nvidia-PRIME hybrid GPU block and its `03-install.sh`
  call site. KDE/KWin handles PRIME on its own.
- greetd / greetd-tuigreet / aquamarine / `AQ_DRM_DEVICES` leave the
  project's vocabulary; SDDM (KDE adapter) is the only display manager.

The **adapter pattern (ADR 0005) is kept**, and `environment.desktop`
stays array-shaped even though it now holds a single value. Adding a
future DE remains a zero-runner-change new directory.

## Considered alternatives
**Rip out the adapter dispatch and array handling** since only one DE
remains — rejected: it contradicts ADR 0005 and would have to be
rebuilt to add any future compositor, for no present gain.

**Keep the hybrid GPU code dormant** in case a Wayland compositor
returns — rejected: it is dead without Hyprland and its comments and
udev rule are pure aquamarine lore that misleads future readers.

## Consequences
- The Tier-2 install matrix loses its Hyprland cells automatically:
  `desktop` is a menu-derived pairwise axis, so shrinking the enum and
  regenerating (`tools/matrix.sh`) drops them — no hand-editing.
- Running machines already on kde+hyprland are unaffected until their
  next reinstall; this change is installer-only.
- Re-adding a Wayland compositor later means re-authoring its adapter
  and, if it needs it, re-deriving the PRIME device-pinning from git
  history.
