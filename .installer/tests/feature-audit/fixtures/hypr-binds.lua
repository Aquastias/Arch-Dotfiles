local terminal = "kitty"
local mainMod = "SUPER"
-- a comment hl.bind("X", nope)
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit())
hl.bind("CTRL + ALT + Delete", hl.dsp.exit())
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
for i = 1, 2 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
end
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
