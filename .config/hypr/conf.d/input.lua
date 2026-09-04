-- Input devices (ADR 0100). Mirrors niri/conf.d/input.kdl. A separate hl.config
-- call from appearance.lua — multiple hl.config calls each apply their keys.
hl.config({
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = false,
        },
    },
})
