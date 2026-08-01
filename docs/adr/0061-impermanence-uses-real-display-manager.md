# Impermanence uses a real display manager; tty1 autologin removed

---
Status: accepted
---

The impermanence tty1 autologin (`_impermanence_setup_autologin`, commit
`b3976cd`, which `exec`s `startplasma-wayland` from a passwordless tty1 login)
and the superseded greetd-swap it replaced are removed. Impermanence hosts now
get a real display-manager login like every other host — SDDM for KDE (and
KDE+Hyprland), greetd+tuigreet for Hyprland-only — where the operator selects a
user and enters a password. The DM survives the rolled-back root via the
machinery that already exists: `_impermanence_relocate_enablements` (mirrors the
DM enablement onto `/usr/lib`, honoured by PID 1's initial boot transaction) and
`_impermanence_graphical_session_fix` (per-user `enable-linger`, an
`XDG_RUNTIME_DIR` fallback, and a boot oneshot that starts `user@$uid` before the
greeter).

The autologin's premise — "on a rolled-back root NO display manager works; the
fault is the DM-initiated login, not the DM" — was drawn **entirely from the
hybrid laptop** (three escalating fixes in one afternoon, 2026-07-28:
linger/XDG → greetd swap → tty1 autologin) and was **never verified on a
single-GPU impermanent host**. ADR 0060 now forbids impermanence on hybrid GPUs,
removing that machine from the matrix, so the over-generalized "DM login is
broken" conclusion no longer holds for any allowed configuration.

## Considered options

- **Keep the autologin as a fallback on impermanence** — rejected: the operator
  wants a real login screen on every boot, and the autologin's motivating
  hardware (impermanence+hybrid) is now un-buildable.
- **Gate the removal behind a HITL smoke-test** on single-GPU impermanence —
  declined by the operator; single-GPU impermanence DM login is assumed good
  until a real install proves otherwise.

## Consequences

- The stale `_impermanence_switch_to_greetd` comment reference (the removed
  greetd swap) is deleted with the autologin.
- If the DM-login race turns out to affect single-GPU impermanence after all,
  the fix is re-enabling the session-fix oneshot's coverage — not restoring the
  autologin.
