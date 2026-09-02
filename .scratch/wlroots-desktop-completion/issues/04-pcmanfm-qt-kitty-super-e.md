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

**Status:** done

- [x] `pcmanfm-qt` installs under `wayland_shell=noctalia`; the [[Package
      Resolver]] reports it; it stays out under `wayland_shell=none`.
      DEVIATION: shipped as a non-negotiable base package in
      `noctalia_preset_packages` (niri.sh), not an install-noctalia.jsonc
      toggle — consistent with kitty ("Noctalia is not a file manager").
- [x] A pcmanfm-qt settings payload (compact view, double-click,
      `Terminal=kitty`) seeds to /etc/skel; F4 / right-click "Open Terminal"
      opens the current folder in kitty (native pcmanfm-qt behavior).
- [x] A trimmed custom-action set seeds (Open in kitty here, Copy path,
      Duplicate); no mount-ISO / Samba / hash, so no `samba` / `fuseiso`.
      DEVIATION: "Edit as root" dropped — it needs a root-GUI dep
      (lxqt-sudo) or fragile pkexec-GUI, against this ticket's own
      tool-present / no-dep-bloat rule.
- [x] `Super+E` is bound to `pcmanfm-qt` on Hyprland (replacing the `dolphin`
      bind) and the same `Mod+E` bind added to the niri `config.kdl`.
- [x] Adapter bats (niri + hyprland) assert the package installs and the
      settings + action payload seed; KDE adapter unaffected.
- [x] No extra theming code — pcmanfm-qt inherits the Noctalia Qt template's
      Rosé Pine colors.

## Comments

Verified: `niri-adapter.bats` (21), `hyprland-adapter.bats` (20),
`resolver.bats` (43), `explain-packages.bats` all green; `shellcheck` clean on
the changed shell files. No VM needed for this ticket.
