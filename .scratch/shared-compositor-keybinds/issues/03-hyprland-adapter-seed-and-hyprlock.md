# 03 — Hyprland adapter seeds the curated config + hyprlock in core

**What to build:** A fresh Hyprland install boots the shared keybinds by default
and can always lock. The Hyprland adapter seeds the curated `hyprland.conf` into
`/etc/skel`, mirroring the niri machinery of ADR 0095: `lib/chroot.sh` stages
the single repo source into the adapter's curated dir (a block parallel to the
existing niri staging), and the adapter copies it into `/etc/skel/.config/hypr/`.
The adapter gains injectable seams `HYPR_SEED_ROOT` and `HYPR_CURATED_DIR`
mirroring niri's `NIRI_SEED_ROOT` / `NIRI_CURATED_DIR`. `hyprlock` is added to
the Hyprland core install so `Super+Alt+L` is never a dead no-op. The adapter
stays core-only for apps otherwise (no launcher, file manager, screenshot tool,
or playerctl — ADR 0096 Q15-a); `hyprlock` is the sole exception.

**Blocked by:** Ticket 02 (needs the curated `hyprland.conf` to stage & seed).

**Status:** ready-for-agent

- [ ] The Hyprland adapter seeds the curated `hyprland.conf` to
      `/etc/skel/.config/hypr/`, as a verbatim copy of the single repo source.
- [ ] `HYPR_SEED_ROOT` and `HYPR_CURATED_DIR` seams exist and default the same
      way niri's equivalents do; `chroot.sh` stages the config into the curated
      dir.
- [ ] `hyprlock` is installed as part of the Hyprland core.
- [ ] The adapter installs no other companion apps — the existing "installs no
      companion packages" behavior still holds.
- [ ] The adapter warns but does not abort when the curated dir is absent
      (mirrors the niri "warns but does not abort" behavior).
- [ ] Hyprland-adapter tests cover: the skel seed + verbatim copy, `hyprlock` in
      core, no other apps, and warn-if-curated-dir-absent.
- [ ] No `hyprlock.conf` is seeded — hyprlock runs on its built-in defaults.
