# 02 — greetd & SDDM Display Manager Adapters

**What to build:** Two self-contained Display Manager Adapters under the new
`extras/dm/<name>/` convention — `dm-greetd` and `dm-sddm` — each owning its
greeter end to end: package install, config generation, and service
enablement. They are not dispatched by anything yet (dead code), so they are
verified in isolation. `dm-greetd` installs greetd + tuigreet and writes the
greeter config pointing tuigreet at the curated wayland-sessions directory.
`dm-sddm` installs and enables SDDM and writes an sddm.conf.d drop-in pinning
`Wayland.SessionDir` (and the X `SessionDir`) to the curated wayland-sessions
directory ahead of the packaged one, so both greeters present the same deduped
session list.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `dm-greetd` installs greetd + greetd-tuigreet, writes the greeter config
      pointing `tuigreet --sessions` at the curated wayland-sessions directory,
      and enables the greetd service.
- [ ] `dm-sddm` installs SDDM, enables it, and writes an sddm.conf.d drop-in
      pinning the curated wayland-sessions directory ahead of `/usr/share` for
      both the Wayland and X session dirs.
- [ ] Each adapter is a subprocess-testable unit with pacman/systemctl stubbed
      and config writes redirected to a temp dir.
- [ ] Two new adapter bats assert package install, service enable, and the
      config / SessionDir drop-in contents (prior art: the KDE and Hyprland
      adapter bats).
- [ ] No existing behavior changes — the adapters are not yet dispatched.
