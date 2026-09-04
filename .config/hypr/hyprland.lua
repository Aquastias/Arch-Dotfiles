-- Curated Hyprland config — stow-owned dotfile, skel-seeded by the installer
-- (ADR 0097, mirroring niri's ADR 0095). Lua, not .conf (ADR 0105): the legacy
-- .conf format is deprecated (dropped in 0.57), so this is the hl.* Lua config;
-- Hyprland auto-loads hyprland.lua ahead of any hyprland.conf. Hosts the SHARED
-- Noctalia shell: the AUTOSTART hook launches Noctalia (the same shell niri
-- runs) and the shared launcher/lock binds drive Noctalia's IPC, so switching
-- compositors changes only the backend. Carries the shared niri<->Hyprland
-- keybind vocabulary; the KEYBINDINGS block matches ~/.config/niri/config.kdl
-- action-for-action on the shared keys. See https://wiki.hypr.land/Configuring/.

------------------
---- MONITORS ----
------------------
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

---------------------
---- MY PROGRAMS ----
---------------------
local terminal = "kitty"
-- pcmanfm-qt is the shared preset file manager (ADR 0100) — niri binds Super+E
-- to the same app. Was dolphin, which the adapter never installed (dead key).
local fileManager = "pcmanfm-qt"
-- Launcher + lock go through Noctalia's IPC (ADR 0097) — the same shell niri
-- runs; niri binds the identical keys to the same actions.
local menu = "noctalia msg panel-toggle launcher"
local lock = "noctalia msg session lock"

-------------------
---- AUTOSTART ----
-------------------
-- Start the shared Noctalia shell (bar, launcher, notifications, lock,
-- wallpaper, OSD) and run the first-login plugin-enable one-shot once (ADR
-- 0093/0097). The one-shot self-guards, so it is a no-op on every later login.
-- hyprland.start fires once at compositor startup, not on config reload — the
-- Lua equivalent of the old `exec-once`.
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia --daemon")
    hl.exec_cmd('sh -c "$HOME/.local/bin/noctalia-enable-plugins"')
    -- Apply the cursor to Hyprland's OWN pointer: env alone is unreliable for
    -- the compositor cursor, so setcursor is the wiki-recommended path (0098).
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------
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

-----------------------
---- LOOK AND FEEL ----
-----------------------
hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 20,
        border_size = 2,
        -- Catppuccin Mocha Lavender borders (ADR 0101) — niri's borders are
        -- palette-driven by Noctalia, but Hyprland's are hardcoded here, so set
        -- them to the same accent: active = lavender->pink (the palette's
        -- primary+secondary), inactive = a muted overlay. Keeps both matching.
        col = {
            active_border = {
                colors = { "rgba(b4befeee)", "rgba(f5c2e7ee)" },
                angle = 45,
            },
            inactive_border = "rgba(6c7086aa)",
        },
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },

    decoration = {
        rounding = 10,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
            color = 0xee1a1a1a,
        },
        blur = {
            enabled = true,
            size = 3,
            passes = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    -- pseudotile is no longer a dwindle option (Hyprland 0.56); it is the
    -- `pseudo` dispatcher, bound under KEYBINDINGS below.
    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = false,
    },

    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = false,
        },
    },
})

-- Animation curves + timings (ADR 0101 look). Same set the legacy .conf carried
-- — bezier definitions become hl.curve, each `animation =` line an hl.animation.
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1} } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1.0} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1} } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

-- No hl.gesture() call: Hyprland 0.56 made swipe opt-in via the `gesture`
-- keyword, so an absent gesture = disabled — which is what we want.

---------------------
---- KEYBINDINGS ----
---------------------
local mainMod = "SUPER"

-- Shared vocabulary (matches ~/.config/niri/config.kdl, ADR 0096).
-- Apps: terminal, close, launcher, file manager, quit, lock.
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit())
hl.bind("CTRL + ALT + Delete", hl.dsp.exit())
hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd(lock))

-- Window state.
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + M", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo()) -- dwindle

-- Focus (arrows + HJKL, matching niri's directional focus).
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

-- Move the focused window (Mod+Ctrl, mirroring niri's move binds).
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.move({ direction = "down" }))
hl.bind(mainMod .. " + CTRL + H", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + CTRL + L", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + CTRL + K", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + CTRL + J", hl.dsp.window.move({ direction = "down" }))

-- Workspaces 1-9 (no 10 — matches niri's dynamic set, ADR 0096), plus move the
-- focused window to a workspace (Mod+Shift — the shared habit).
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- ── Hyprland-only extras (niri has no equivalent, ADR 0096) ──
-- Scratchpad (special workspace).
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through workspaces with Mod + mouse wheel.
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with Mod + LMB/RMB drag (niri does this natively).
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Volume / brightness (allow while locked, key-repeat; shared with niri).
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Media keys (playerctl — shipped by the Noctalia preset, ADR 0097).
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

------------------------------
---- WINDOWS AND WORKSPACES --
------------------------------
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
