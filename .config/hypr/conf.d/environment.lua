-- Monitors + environment (ADR 0098/0102). Mirrors niri/conf.d/environment.kdl
-- (niri models the cursor via cursor{}; niri omits outputs on purpose, ADR
-- 0094, so its mirror carries no monitor line).

-- Let Hyprland auto-arrange every output at its preferred mode — host-specific
-- display state is intentionally not pinned in the portable curated config.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- Default cursor: Bibata Modern Ice, the fleet default shared with KDE/niri
-- (ADR 0098). hyprcursor is primary; XCURSOR is the XWayland/legacy fallback.
-- One AUR package (bibata-cursor-git) ships both formats in one theme dir.
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "24")

-- Route Qt apps through qt6ct so they follow Noctalia's palette — App Theming
-- Bridge (ADR 0102). Set here (niri uses its environment{} node), not via
-- environment.d: start-hyprland is not the systemd-user session (ADR 0070).
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
