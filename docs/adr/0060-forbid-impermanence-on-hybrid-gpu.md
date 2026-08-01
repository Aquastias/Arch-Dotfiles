# Forbid impermanence on hybrid AMD+NVIDIA GPUs

---
Status: accepted
---

Enabling `options.impermanence` on a hybrid AMD+NVIDIA laptop (the Legion-class
box, `gpu` resolving to both `amd` and `nvidia`) is now a hard validation error,
regardless of the selected desktop. On a rolled-back impermanent root the
graphical login hits a logind-session race — `pam_systemd` cannot register a
session against the freshly mounted ZFS datasets, `XDG_RUNTIME_DIR` is never set,
and `kwin_wayland` (or any compositor) dies "Could not create wayland socket" →
black screen. This was verified on the hybrid laptop and was originally
misdiagnosed as an SDDM DRM-master handoff failure (reverted commit `a5b429d`);
the durable fix was disabling impermanence on that machine. The rule codifies
that: impermanence is gated by hardware, not by desktop choice, so Hyprland and
KDE remain freely selectable on any host while the known-bad
impermanence+hybrid combination can no longer be assembled.

## Considered options

- **Warning only** — rejected: the combination reliably black-screens, so
  proceeding is never the right outcome.
- **Gate the desktop instead of impermanence** — rejected: the fault is the
  impermanence logind race, which is GPU/DE-agnostic; the hybrid GPU is the
  variable that turned a working setup bad, so the ban targets that combination.

## Consequences

- The check runs after GPU Resolution, since `gpu: "auto"` only resolves to the
  `amd`+`nvidia` pair at install time.
- The impermanence logind-race fixes (tty1 autologin, linger, XDG_RUNTIME_DIR
  fallback) remain necessary on non-hybrid impermanent hosts (eterniox); this
  ADR removes only the hybrid variable, not the session-launch machinery.
