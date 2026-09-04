-- Autostart the shared Noctalia shell (ADR 0093/0097). Mirrors
-- niri/conf.d/autostart.kdl's spawn-at-startup lines. hyprland.start fires once
-- at compositor startup, not on config reload — the Lua equivalent of the old
-- `exec-once`. The plugin-enable one-shot self-guards, so it is a no-op on every
-- later login.
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia --daemon")
    hl.exec_cmd('sh -c "$HOME/.local/bin/noctalia-enable-plugins"')
    -- Apply the cursor to Hyprland's OWN pointer: env alone is unreliable for
    -- the compositor cursor, so setcursor is the wiki-recommended path (0098).
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")
end)
