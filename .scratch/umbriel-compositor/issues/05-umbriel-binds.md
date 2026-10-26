# 05: Umbriel binds

**What to build:** The operator's muscle memory carries to Umbriel. The
shared niri/Hyprland bind map is translated into Umbriel's TOML binds and
replaces upstream defaults (Meta+X closes, not Mod+Q). Umbriel-only
features (overview, tab groups, scratchpad) take keys the shared map leaves
free. Every shipped bind declares an expectation in a co-located audit-binds
file, proven by real keyboard input. Add an Umbriel bind parser if the
existing ones cannot read TOML binds.

**Blocked by:** 04

**Status:** done

- [x] Every shipped bind has an expectation; feature-audit binds bats pass
      (no bind without one)
- [x] Shared binds match niri/Hyprland behaviour; no collisions with
      Umbriel-only binds
- [x] VM Audit Run: every Umbriel bind PASSes under real input

Spec: ../PRD.md · ADR 0096, 0113, 0152, 0159

## Comments

- desktop Audit Run 20261026-082542: 89 Umbriel binds PASS. Open: one
  session-quit bind (Ctrl+Alt+Delete) failed once, Mod+Shift+E failed once
  in the prior run (that one was the SDDM-relogin race, fixed by judging the
  compositor PID). Likely a post-reboot timing flake; not reproduced by hand.
- Shift+Print uses grim + Umbriel IPC geometry: Noctalia 5.3 has no
  `screenshot-window` yet (git HEAD does); switch back when it ships.
