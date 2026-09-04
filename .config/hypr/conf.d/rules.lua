-- Window rules (ADR 0105). Mirrors niri/conf.d/rules.kdl (rounding, though, is
-- decoration on Hyprland — see appearance.lua).
-- Ignore maximize requests from all apps (the old suppress_event maximize).
hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})
-- Never focus a nameless XWayland surface (the old no_focus xwayland rule).
hl.window_rule({
    name = "no-focus-empty-xwayland",
    match = { class = "^$", title = "^$", xwayland = true },
    no_focus = true,
})
