# PRD: Hyprland Lua config + VM cursor artifacts (retroactive)

Status: done

Retroactive record — shipped without a grill session. Anchored by
[[ADR 0105]] (Hyprland `.conf` → Lua) and [[ADR 0106]] (VM SPICE cursor
artifact, per-surface overrides).

## What shipped

- Curated Hyprland config migrated to Lua; syntax updated for Hyprland 0.56.
- VM-only software-cursor overrides: Hyprland software cursor, niri cursor
  plane disabled, SDDM Xorg `SWcursor`; gated so real hardware is untouched.

## Commits

216ac18, cfb9afa, b016757, d6ef402, 1e14e2a.
