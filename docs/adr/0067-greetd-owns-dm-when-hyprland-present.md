# greetd owns the display manager whenever Hyprland is installed

---
Status: superseded by ADR 0068
---

## Superseded (2026-08-23)

The root cause below — an SDDM-launched Hyprland session never granted DRM
master — was fixed by giving seatd the master, independent of the greeter
(ADR 0068). SDDM launches Hyprland reliably now, so the auto→greetd co-install
rule is withdrawn: **`auto` resolves to `sddm` for any desktop, fleet-wide**
(`_resolve_env_display_manager`), and greetd is explicit-opt-in only. The SDDM
adapter already owns the sole-Hyprland case (installs + enables + curates
sessions). The analysis below is retained as the historical record of why
greetd was once required.

greetd + greetd-tuigreet is now the display manager whenever Hyprland is
installed — a sole-Hyprland install **and** a KDE+Hyprland co-install. Under ADR
0062 the KDE adapter owned the DM (SDDM) on any co-install and greetd only ran
when Hyprland was the sole desktop; that co-install path **never lit the panel
for Hyprland**.

Root cause, from aquamarine's own log on a single AMD (Phoenix) iGPU: an
SDDM-launched Hyprland session runs the DRM backend, finds `eDP-1` at its
preferred mode, then the atomic KMS commit fails repeatedly with `atomic drm
request: failed to commit: Permission denied`. That is a **DRM-master** failure
— logind does not consider the SDDM-launched aquamarine session *active* on
`seat0`, so it never grants master. kwin negotiates the same handoff and works,
which is why KDE is unaffected; a bare-TTY `dbus-run-session Hyprland` also
works, because there Hyprland is the compositor on the active VT and takes
master directly. greetd/tuigreet launches the compositor the same
compositor-first way, so aquamarine gets master. No `AQ_*` env fixes this — a
non-active session cannot become DRM master (upstream Hyprland #2696, #8586).

A second, independent aquamarine failure was fixed alongside it: if
`WAYLAND_DISPLAY`/`DISPLAY` are set (a prior Plasma Wayland session leaves them
in the lingering `user@` manager), aquamarine picks its **nested** Wayland
backend and renders into an invisible parent window instead of the panel. The
Hyprland session override's `Exec` now runs `env -u WAYLAND_DISPLAY -u DISPLAY
Hyprland` to force the DRM backend.

## Considered options

- **Keep SDDM for the co-install and fix its handoff** — rejected: no reliable
  SDDM-side fix was found for the seat-activation/DRM-master failure, and the
  compositor-first greetd launch is the path already proven to work (sole
  Hyprland + the bare-TTY test).
- **Force legacy modesetting (`AQ_NO_ATOMIC=1`)** — rejected: the failure is
  "no DRM master," not atomic-vs-legacy; a legacy commit needs master too.
- **Drop Hyprland from co-installs** — rejected: the user wants both; greetd
  makes both work.

## Consequences

- On a co-install `sddm` is installed but left disabled; greetd is enabled. The
  KDE adapter enables SDDM only for a KDE-only install.
- tuigreet is pointed at a curated `/usr/local/share/wayland-sessions`
  containing the direct-launch Hyprland override plus Plasma (symlinked in), so
  the packaged crashy `start-hyprland` session and the `uwsm` variant in
  `/usr/share` never appear in the picker; both DEs stay selectable (F3).
- A KDE co-install now greets with tuigreet's TUI instead of SDDM's graphical
  greeter — the trade for a Hyprland session that actually starts.
- Under impermanence the greetd enablement is mirrored onto `/usr/lib` by the
  same machinery as any DM (ADR 0061), so it survives the rolled-back root.
