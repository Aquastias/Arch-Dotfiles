-- Input devices (ADR 0100). Mirrors niri/conf.d/input.kdl. A separate hl.config
-- call from appearance.lua — multiple hl.config calls each apply their keys.
hl.config({
    input = {
        kb_layout = "us",
        -- Click-to-focus, hover still scrolls (ADR 0147): hovering never
        -- steals focus mid-menu. Matches niri's default.
        follow_mouse = 2,
        -- Default 1 still refocuses on tiled<->floating crossings, so a
        -- dialog's menu closed when the pointer crossed a tiled window.
        float_switch_override_focus = 0,
        sensitivity = 0,
        touchpad = {
            natural_scroll = false,
        },
    },
    -- ANR dialog takes focus; 3x the default 5 missed pings spares apps that
    -- are only slow to start, hung ones still get it (ADR 0147).
    misc = {
        anr_missed_pings = 15,
    },
    -- The update-news and donation popups also take focus (ADR 0147).
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
})
