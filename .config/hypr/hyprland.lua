-- Curated Hyprland config — stow-owned dotfile, skel-seeded by the installer
-- (ADR 0097, mirroring niri's ADR 0095). Lua, not .conf (ADR 0105): the legacy
-- .conf format is deprecated (dropped in 0.57), so this is the hl.* Lua config;
-- Hyprland auto-loads hyprland.lua ahead of any hyprland.conf. Hosts the SHARED
-- Noctalia shell and the shared niri<->Hyprland keybind vocabulary (ADR 0096).
-- See https://wiki.hypr.land/Configuring/.
--
-- This entry file is a pure manifest (ADR 0107): every setting lives in a
-- conf.d/ part-file, mirrored one-for-one with ~/.config/niri/conf.d/. Each
-- require() is a separate Lua scope, so every part-file is self-contained.
--
-- The `conf.d` dir name contains a dot, which Lua's require() would read as a
-- path separator, so we put conf.d/ on package.path (resolved from this file's
-- own location) and require each part by its bare basename.
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
package.path = here .. "conf.d/?.lua;" .. package.path

require("environment")
require("input")
require("appearance")
require("autostart")
require("keybinds")
require("media")
require("rules")
