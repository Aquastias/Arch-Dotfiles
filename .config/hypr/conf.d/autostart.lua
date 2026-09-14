-- Autostart the shared Noctalia shell (ADR 0093/0097). Mirrors
-- niri/conf.d/autostart.kdl's spawn-at-startup lines. hyprland.start fires once
-- at compositor startup, not on config reload — the Lua equivalent of the old
-- `exec-once`. The plugin-enable one-shot self-guards, so it is a no-op on every
-- later login.
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia --daemon")
    hl.exec_cmd('sh -c "$HOME/.local/bin/noctalia-enable-plugins"')
    -- Live Theme Bridge (ADR 0116): repaint running Qt6/GTK3 apps on a Noctalia
    -- theme change. Long-lived; dies with the session.
    hl.exec_cmd('sh -c "$HOME/.local/bin/noctalia-theme-bridge"')
    -- XDG user dirs (ADR 0131): Hyprland doesn't run /etc/xdg/autostart, so
    -- generate the standard dirs + ~/Projects here. Idempotent.
    hl.exec_cmd('sh -c "$HOME/.local/bin/noctalia-xdg-user-dirs"')
    -- Apply the cursor to Hyprland's OWN pointer: env alone is unreliable for
    -- the compositor cursor, so setcursor is the wiki-recommended path (0098).
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")
    -- Reassert the shared gsettings cursor into Bibata (ADR 0123): on a combined
    -- box a KDE cursor change rewrites the SHARED gsettings cursor-theme, which a
    -- GTK app here could otherwise inherit. XCURSOR env covers XWayland; this is
    -- the GTK belt. No-op on a pure box (already Bibata).
    hl.exec_cmd('sh -c "gsettings set org.gnome.desktop.interface cursor-theme '
      .. 'Bibata-Modern-Ice; gsettings set org.gnome.desktop.interface '
      .. 'cursor-size 24"')
end)
