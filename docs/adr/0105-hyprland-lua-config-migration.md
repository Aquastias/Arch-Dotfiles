# Migrate the curated Hyprland config from `.conf` to Lua

---
Status: accepted. **Supersedes the `.conf` delivery in ADR 0096** (curated
`hyprland.conf` seeded via `/etc/skel`) and updates the Hyprland leg of ADR
0097/0098/0101/0102 (Noctalia wiring, Bibata cursor, Catppuccin borders, qt6ct
env). niri's KDL config (ADR 0095) is unaffected.
---

Hyprland 0.56 prints a deprecation toaster on every launch: the legacy `.conf`
(hyprlang) format is going away, **removed in 0.57**. The compositor now ships a
first-class Lua config (`hl.*` API) and, when both exist, **prefers
`hyprland.lua` over `hyprland.conf`** (`getMainConfigPath` checks Lua first).
Rather than carry a format with a known removal date, the curated compositor
config is rewritten as `.config/hypr/hyprland.lua` and the legacy `.conf` is
deleted from the stow payload.

## Decision

Translate the curated config one-to-one into the Lua API, preserving every
binding, rule, env, and the ADR-anchored look:

- `exec-once` → a single `hl.on("hyprland.start", …)` hook (fires at startup,
  not on reload — the exact `exec-once` semantics).
- `env =` → `hl.env(name, value)`; `bind*=` → `hl.bind(keys, hl.dsp.…, opts)`
  where `opts` carries `{ locked, repeating, mouse }` (the old `l`/`e`/`m`
  suffixes); `windowrule =` → `hl.window_rule{ match = {…}, … }`; the
  `general`/`decoration`/`animations`/`dwindle`/`master`/`misc`/`input` blocks →
  `hl.config{}`; beziers → `hl.curve`, animation lines → `hl.animation`.
- The installer follows the rename: chroot.sh stages `hyprland.lua`, the
  Hyprland adapter seeds it (`_hc=".config/hypr/hyprland.lua"`), and the
  VM-only software-cursor override (injected by the preset, never shipped)
  switches its Hyprland branch from a `cursor {}` stanza to
  `hl.config({ cursor = { no_hardware_cursors = true } })`.

Every construct was verified against the exact shipped binary (0.56.2): its Lua
config manager runs the script at parse time and reports Lua errors **and**
`configError`s from bad dispatcher arguments, so `Hyprland --verify-config -c
hyprland.lua` validates the whole config offline — the same green-gate the
`.conf` had (`niri validate`'s peer). The dispatcher arg shapes
(`window.fullscreen{ mode = "maximized" }`, `window.move{ direction = "left" }`,
`focus{ workspace = N }`, `exit()`) were read from
`src/config/lua/bindings/LuaBindingsDispatchers.cpp` at the v0.56.2 tag, not
guessed.

## Considered options

- **Defer until 0.57 actually ships** (keep `.conf`, live with the toaster). The
  format still works on 0.56.2, so this was low-risk — but rejected: the Lua API
  is already stable and fully validatable *today*, the migration is a pure
  translation with a green gate, and doing it now removes a dated dependency
  before it becomes an emergency. Chosen over waiting.
- **Ship both `hyprland.lua` and `hyprland.conf`** (belt-and-suspenders). Lua
  wins the precedence check, so the `.conf` would be dead bytes that only invite
  drift. Rejected — one source of truth.
- **Auto-convert.** Hyprland ships no `--convert`; there is no mechanical path.
  Hand translation was the only option, which is why the offline `--verify-config`
  gate matters.

## Consequences

- The launch-time deprecation toaster is gone; the config survives the 0.57
  `.conf` removal untouched.
- The keybind vocabulary still matches niri action-for-action (ADR 0096) — the
  translation changed syntax, not behavior. The `hl.dsp.exit()` binds, Bibata
  hyprcursor env, Catppuccin gradient border, and `QT_QPA_PLATFORMTHEME=qt6ct`
  all carry over verbatim.
- The drift/adapter tests key off `hyprland.lua` (content asserts rewritten to
  the `hl.*` forms); the seed and staging paths follow the rename.
- **Requires Hyprland ≥ 0.54** (Lua config landed there). The fleet pins current
  Arch `hyprland` (0.56.2), well past that floor, so no practical constraint —
  but a hard downgrade below 0.54 would no longer find a config.
