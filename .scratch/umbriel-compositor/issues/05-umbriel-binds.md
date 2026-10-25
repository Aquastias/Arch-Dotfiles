# 05: Umbriel binds

**What to build:** The operator's muscle memory carries to Umbriel. The
shared niri/Hyprland bind map is translated into Umbriel's TOML binds and
replaces upstream defaults (Meta+X closes, not Mod+Q). Umbriel-only
features (overview, tab groups, scratchpad) take keys the shared map leaves
free. Every shipped bind declares an expectation in a co-located audit-binds
file, proven by real keyboard input. Add an Umbriel bind parser if the
existing ones cannot read TOML binds.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Every shipped bind has an expectation; feature-audit binds bats pass
      (no bind without one)
- [ ] Shared binds match niri/Hyprland behaviour; no collisions with
      Umbriel-only binds
- [ ] VM Audit Run: every Umbriel bind PASSes under real input

Spec: ../PRD.md · ADR 0096, 0113, 0152, 0159
