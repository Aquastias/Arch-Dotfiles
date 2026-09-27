# Impermanence uses a real display manager; remove autologin

Status: done (6719e92)

## Parent

`.scratch/hyprland-readd/PRD.md` (ADR 0061)

## What to build

Impermanence hosts reach a real display-manager login on every boot — select a
user, type a password — instead of a tty1 autologin. The impermanence apply
sequence no longer disables the display manager or auto-logs-in the primary user
on tty1, and the stale reference to the removed greetd-swap is deleted. The
existing enablement relocation (mirroring the DM enablement onto the
never-rolled-back tree) and the graphical-session hardening (per-user linger,
`XDG_RUNTIME_DIR` fallback, pre-greeter user-manager oneshot) are retained so
the DM login survives the rolled-back root.

## Acceptance criteria

- [x] The tty1 autologin step is removed from the impermanence apply sequence
- [x] The stale greetd-swap comment reference is removed
- [x] With `ROOT` redirected, the DM (SDDM) remains enabled on a rolled-back root
- [x] Enablement relocation and graphical-session hardening still applied
- [x] `chroot-impermanence.bats` updated (autologin assertions removed; DM-stays-
      enabled + session-fix assertions added) and green

## Blocked by

- None — can start immediately

## Comments

- 2026-09-27 audit: 6719e92, 93eca37. Later: impermanence DM login reworked by
  ADR 0067→0069 (greetd then operator-chosen DM) and the uwsm session dropped
  (ADR 0070).
