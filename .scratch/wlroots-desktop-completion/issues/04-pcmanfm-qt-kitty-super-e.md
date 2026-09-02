# 04 — pcmanfm-qt + kitty custom actions + Super+E parity

**What to build:** `Super+E` opens a working file manager on both niri and
Hyprland, and the operator can drop into kitty at the current folder.
`pcmanfm-qt` ships in the Noctalia preset with a compact-view / tree+Places /
double-click layout, opens the current folder in kitty from F4 and from a
right-click "Open in kitty here" action, and carries a lean action set (Open in
kitty, Copy path, Edit as root, Duplicate). It matches Rosé Pine with no extra
theming. The dead `Super+E`→`dolphin` bind on Hyprland is fixed and the same
bind is added to niri.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `pcmanfm-qt` is declared in `install-noctalia.jsonc` and installs under
      `wayland_shell=noctalia`; the [[Package Resolver]] reports it; it stays
      out under `wayland_shell=none`.
- [ ] A pcmanfm-qt settings payload (compact view, tree+Places, double-click,
      `Terminal=kitty`) seeds to /etc/skel; F4 / right-click "Open Terminal"
      opens the current folder in kitty.
- [ ] A trimmed custom-action set seeds (Open in kitty here, Copy path, Edit as
      root, Duplicate); mount-ISO / Samba-share / hash actions are NOT shipped,
      so no `samba` / `fuseiso` is pulled in.
- [ ] `Super+E` is bound to `pcmanfm-qt` on Hyprland (replacing the `dolphin`
      bind) and the same bind is added to the niri `config.kdl`.
- [ ] Adapter bats assert the package installs and the settings + action payload
      seed; the KDE adapter is unaffected.
- [ ] No extra theming code — pcmanfm-qt inherits the Noctalia Qt template's
      Rosé Pine colors.
