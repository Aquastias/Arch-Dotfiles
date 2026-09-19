-- Noctalia user-template (stowed input), registered as
-- theme.templates.user.nvim (ADR 0136). Noctalia substitutes the palette's
-- terminal + Material roles on every change in a compositor session and writes
-- the resolved output to ~/.config/nvim/themes/noctalia.lua, which nvim's
-- config/noctalia.lua loads. This input is the only stowed half; the output is
-- seed-only/gitignored. Body mirrors the base16 mapping kitty uses so the two
-- terminals stay coherent.
--
-- Engine rule (VM-verified, ADR 0129): never write a double-brace color tag in
-- a COMMENT — the engine parses comments too, so a placeholder there becomes a
-- real (and, if it names a missing role, failing) tag.
return {
  base00 = "{{colors.terminal_background.default.hex}}",
  base01 = "{{colors.surface_container.default.hex}}",
  base02 = "{{colors.surface_container_highest.default.hex}}",
  base03 = "{{colors.terminal_bright_black.default.hex}}",
  base04 = "{{colors.on_surface_variant.default.hex}}",
  base05 = "{{colors.on_surface.default.hex}}",
  base06 = "{{colors.terminal_foreground.default.hex}}",
  base07 = "{{colors.terminal_bright_white.default.hex}}",
  base08 = "{{colors.terminal_normal_red.default.hex}}",
  base09 = "{{colors.terminal_normal_yellow.default.hex}}",
  base0A = "{{colors.terminal_normal_yellow.default.hex}}",
  base0B = "{{colors.terminal_normal_green.default.hex}}",
  base0C = "{{colors.terminal_normal_cyan.default.hex}}",
  base0D = "{{colors.terminal_normal_blue.default.hex}}",
  base0E = "{{colors.terminal_normal_magenta.default.hex}}",
  base0F = "{{colors.terminal_bright_red.default.hex}}",
  accent = "{{colors.primary.default.hex}}",
}
