# Split the curated niri/Hyprland configs into `conf.d/` part-files

---
Status: accepted. **Supersedes the single-file *delivery* of ADR 0095**
(skel-seeded `config.kdl`) **and 0105** (skel-seeded `hyprland.lua`), and the
seed leg of ADR 0097. Their content, wiring, keybind-parity (0096), and format
(KDL / Lua, 0105) decisions are unchanged — only the on-disk file count and the
seed/stage/test paths move. The VM software-cursor override (ADR 0106) relocates
its append target.
---

The two curated compositor configs had each grown to a single ~240-line file
(`config.kdl`, `hyprland.lua`) mixing input, appearance, autostart, keybinds,
media keys, and window rules. Both compositors now ship a native split
mechanism, so the monolith is broken into one **symmetric, human-readable set of
category files** shared across both compositors — the same folder shape on each
so switching compositors reads the same on disk, not just at the keyboard.

## Decision

Each entry file (`config.kdl` / `hyprland.lua` — the compositors hard-require
those exact names) becomes a **pure manifest**: a header plus ordered
include/require lines. All settings move into a sibling `conf.d/` dir holding
seven parallel part-files per side:

`environment`, `input`, `appearance`, `autostart`, `keybinds`, `media`, `rules`.

- **niri** uses `include "conf.d/NAME.kdl"` (top-level only, since 25.11; the
  fleet pulls bare Arch `niri`, well past that floor). `binds{}` blocks **merge
  by key** across includes (keybinds vs media use disjoint keys → lossless);
  window-rules accumulate positionally, so the manifest order is fixed.
- **Hyprland** uses `require("conf.d.NAME")` (Lua, ≥ 0.55; fleet on 0.56.2).
  Each `require` is a **separate Lua scope**, so every part-file is
  self-contained — the `terminal`/`menu`/`lock`/`mainMod` locals live wholly in
  `keybinds.lua` (autostart uses literals), needing no cross-file globals.
  Multiple `hl.config{}` calls each apply their sub-table (the ADR 0106
  VM-override already relies on this).
- **Rounded corners are an idiom split, not an asymmetry in structure:** niri
  models rounding as a `window-rule` (→ `rules.kdl`); Hyprland's is
  `decoration.rounding` (→ `appearance.lua`). File names stay identical; content
  follows each compositor's native model.
- **Installer follows the fan-out.** `chroot.sh` stages the entry file **plus**
  its `conf.d/` tree into each curated dir; `noctalia-preset.sh` seeds the whole
  tree into `/etc/skel`. The VM software-cursor override (ADR 0106) now appends
  to `conf.d/environment.{kdl,lua}` — where cursor config lives — so even the
  seeded entry file stays a pure manifest.

## Considered options

- **Leave the configs monolithic.** Rejected: the split is the whole ask, and
  both formats support it natively with an offline green gate, so there is no
  reason to carry a 240-line mixed file.
- **Flat part-files beside the entry file** (no `conf.d/`). Rejected: clutters
  the compositor's own dir; `conf.d/` is the familiar Unix idiom and keeps the
  entry file visually alone as the table of contents.
- **A shared Hyprland `programs` module** returning a table for the app/menu
  locals. Rejected: it has no niri counterpart (niri inlines those strings), so
  it would break the symmetric file set — and the locals turn out to be confined
  to `keybinds.lua` anyway, so no shared module is needed.
- **Keep appending the VM cursor override to the entry file.** Rejected in
  favor of `conf.d/environment`: keeps the seeded manifest pure and puts the
  override next to the rest of the cursor config.

## Consequences

- Both configs validate offline unchanged: `niri validate` and `Hyprland
  --verify-config -c hyprland.lua` (ADR 0105's gate) parse the manifest +
  includes/requires as one config.
- The repo files stay a single-source stow package (now a tree) and the
  installer still seeds, never stows (ADR 0095) — the seed just copies a
  directory instead of one file.
- Drift/adapter tests re-point their content asserts at the specific part-file
  now holding each construct (autostart, cursor, IPC binds); the skel-seed tests
  cover the `conf.d/` tree, not a lone file.
- Adding a future setting means editing the one part-file for its category — the
  reason the split exists.
