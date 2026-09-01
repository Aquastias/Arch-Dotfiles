# 02 — Hyprland shared keybinds authored & version-controlled

**What to build:** A new curated `hyprland.conf` in the dotfiles repo carrying
the converged keybind vocabulary (ADR 0096) in Hyprland dialect — the same
shared binds as the niri config, plus the Hyprland-only extras (file manager
`Super+E`, scratchpad `Super+S`/`Super+Shift+S`). Hyprland's awkward stock
letters are rebound (`Q`→close, terminal→`Return`, launcher→`D`, exit→
`Super+Shift+E`), fullscreen is added on `Super+F` (stock had none), directional
window-move on `Super+Ctrl`+arrows/HJKL is added, and the lock bind
`Super+Alt+L` spawns `hyprlock`. The file is an ordinary stow-able source, so
the operator's current Hyprland machine picks up the shared layout via stow, and
the config is no longer an uncommitted stock file living outside the repo.

**Blocked by:** None — can start immediately. (Design is frozen in ADR 0096 +
the spec; use the same design table as ticket 01 so the two dialects stay in
lockstep.)

**Status:** ready-for-agent

- [ ] A curated `hyprland.conf` exists in the repo as a single stow-able source.
- [ ] Every shared bind matches the niri config's semantics on the same keys
      (terminal, close, launcher, quit, fullscreen, float, focus, move,
      workspaces `1`–`9`, move-to-workspace `Super+Shift`+`<n>`, lock, drag
      move/resize, volume/brightness/media keys).
- [ ] Hyprland-only binds present: `Super+E` file manager, `Super+S` /
      `Super+Shift+S` scratchpad.
- [ ] Workspace 10 / `Super+0` is dropped; stock `Print` stays unbound (no
      screenshot tool in core-only).
- [ ] The launcher (`wofi`), file manager (`dolphin`), and `playerctl` binds are
      present but remain operator-supplied — the config assumes nothing is
      installed by the adapter except the lock (ticket 03).
- [ ] The config is valid Hyprland syntax (loads without error in a running
      Hyprland).
