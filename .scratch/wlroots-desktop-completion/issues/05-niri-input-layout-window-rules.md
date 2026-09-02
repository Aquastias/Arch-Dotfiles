# 05 — niri input / layout / window-rules tuning

**What to build:** A fresh niri+Noctalia login feels tuned, not raw. The curated
`config.kdl` gains an `input` block (touchpad tap-to-click + natural-scroll,
keyboard layout/repeat), a minimal `layout` block, and `window-rules`. Display
scale/mode is deliberately left out — `output` is host-specific and would break
the curated config's portability (ADR 0094/0100). Hyprland already carries its
equivalent input/monitor/look blocks, so this ticket is niri-only.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] The curated `config.kdl` gains an `input` block: touchpad tap-to-click,
      natural-scroll, disable-while-typing, clickfinger; keyboard layout +
      repeat.
- [x] The curated `config.kdl` gains a minimal `layout` block (gaps +
      preset/default column widths) and a `window-rule` (rounded corners,
      niri parallel to Hyprland's rounding). Colors left to Noctalia's template.
- [x] No `output` block is added (portability rule).
- [x] Adapter bats stay green (they stub config.kdl, so the seeding mechanism
      is covered; content is not adapter-tested by design).
- [ ] `niri validate` lint — SKIPPED: niri binary is not available in this
      environment/CI. Brace-balance checked (122/122); author-verified KDL.

## Comments

Content correctness (niri accepting the new blocks, idle/input actually
behaving) is provable only at Seam 2 (desktop-verify VM) or a local `niri
validate` — neither runnable here. KDL authored against niri's schema.
