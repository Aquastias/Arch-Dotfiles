# Split curated niri/Hyprland configs into `conf.d/` part-files

**Status:** ready-for-agent

Anchored by ADR 0107 (supersedes the single-file delivery of ADR 0095/0105 and
the seed leg of 0097; relocates the VM override of 0106). Keeps every content,
wiring, keybind-parity (0096), and format (KDL/Lua, 0105) decision intact.

## Problem Statement

Both curated compositor configs are now stable but each is a single ~240-line
file — `.config/niri/config.kdl` and `.config/hypr/hyprland.lua` — mixing input,
appearance, autostart, keybinds, media keys, and window rules. Finding or
editing one concern means scrolling a monolith, and the two files don't share a
visible organizing shape even though they run the same shared Noctalia shell and
the same keybind vocabulary. The operator wants each config broken into
smaller, purpose-named files, with an **identical, human-readable folder
structure across both compositors**, purely for organization — no behavior
change.

## Solution

Each entry file (`config.kdl` / `hyprland.lua`, whose names both compositors
hard-require) becomes a **pure manifest**: a header comment plus an ordered list
of native include/require lines. All real settings move into a sibling
`conf.d/` directory holding seven parallel part-files, the same names on both
sides:

```
.config/niri/                      .config/hypr/
├── config.kdl   (manifest)        ├── hyprland.lua  (manifest)
└── conf.d/                        └── conf.d/
    ├── environment.kdl                ├── environment.lua
    ├── input.kdl                      ├── input.lua
    ├── appearance.kdl                 ├── appearance.lua
    ├── autostart.kdl                  ├── autostart.lua
    ├── keybinds.kdl                   ├── keybinds.lua
    ├── media.kdl                      ├── media.lua
    └── rules.kdl                      └── rules.lua
```

- niri uses `include "conf.d/NAME.kdl"` (top-level, since 25.11).
- Hyprland uses `require("conf.d.NAME")` (Lua, ≥ 0.55; fleet on 0.56.2).

Manifest order is fixed: environment, input, appearance, autostart, keybinds,
media, rules. The split is a pure move — every binding, rule, env, spawn, and
look value carries over verbatim; both configs still validate offline and behave
identically.

## User Stories

1. As the operator, I want each compositor config broken into purpose-named
   files, so that I can open `keybinds` without scrolling past input and
   animation config.
2. As the operator, I want niri and Hyprland to share the exact same `conf.d/`
   filenames, so that switching compositors feels like the same layout on disk,
   not just at the keyboard.
3. As the operator, I want the entry file to read as a table of contents, so
   that I can see every concern the config covers at a glance.
4. As the operator, I want hardware media keys (volume, brightness, playerctl)
   in their own `media` file separate from the main `keybinds`, so that the two
   concerns don't intermingle.
5. As the operator, I want the split to change zero behavior, so that a fresh
   login looks and acts exactly as it did before the reorg.
6. As the operator, I want each part-file to carry a focused header comment
   with its own ADR anchors, so that the *why* stays next to the *what*.
7. As the operator, I want the repo files to remain a single-source stow
   package, so that `stow .` on my own machine still delivers the whole tree.
8. As a fresh-install user, I want the installer to seed the whole `conf.d/`
   tree into `/etc/skel`, so that a new box boots the full curated look with no
   operator action, exactly as before.
9. As a fresh-install user on a VM, I want the software-cursor override still
   applied, so that the pointer does not render as a broken "X" — now injected
   into `conf.d/environment` rather than the entry file.
10. As a maintainer, I want the drift guards to assert curated content against
    the specific part-file that holds it, so that an accidental content
    regression is still caught after the split.
11. As a maintainer, I want the adapter tests to prove the `conf.d/` tree is
    seeded to skel, so that a broken seed path fails CI instead of a fresh box.
12. As a maintainer, I want both configs to pass their offline validators after
    the split, so that a bad include/require path is caught before shipping.
13. As the operator, I want niri's rounded-corner rule and Hyprland's
    `decoration.rounding` each placed where its compositor natively models
    rounding, so that neither file fights its own idiom even though the file
    names stay identical.
14. As the operator, I want to add a future setting by editing exactly one
    category file, so that the config's organization pays off on the next edit.

## Implementation Decisions

- **Entry files become manifests.** `config.kdl` and `hyprland.lua` contain only
  a header comment and the ordered include/require lines. No settings remain in
  them.
- **`conf.d/` part-file set (both sides):** environment, input, appearance,
  autostart, keybinds, media, rules. Content mapping:
  - *environment* — niri `cursor{}` + `environment{}`; Hyprland `hl.monitor` +
    `hl.env` (cursor + qt). The single `hl.monitor` line folds here (niri has no
    output block by design, ADR 0094).
  - *input* — niri `input{}`; Hyprland `hl.config{ input = … }`.
  - *appearance* — niri `hotkey-overlay{}` + `layout{}`; Hyprland the
    `general/decoration/animations/dwindle/master/misc` `hl.config` block plus
    `hl.curve` and `hl.animation` lines.
  - *autostart* — niri two `spawn-at-startup`; Hyprland the single
    `hl.on("hyprland.start", …)` hook.
  - *keybinds* — the main bind set (apps, window state, focus, move, workspaces,
    screenshots, niri-only column/overview extras, Hyprland scratchpad/mouse).
    Hyprland's `terminal`/`fileManager`/`menu`/`lock`/`mainMod` locals are
    declared at the top of `keybinds.lua` (they are used nowhere else).
  - *media* — hardware keys only: volume, brightness, playerctl.
  - *rules* — niri `window-rule` (corner-radius, its only rule); Hyprland the
    two `hl.window_rule` (suppress-maximize, no-focus-empty-xwayland).
- **Rounding idiom split (deliberate).** niri models rounded corners as a
  `window-rule`, so it lives in `rules.kdl`; Hyprland's rounding is
  `decoration.rounding`, so it lives in `appearance.lua`. File names stay
  symmetric; content follows each compositor's native model. Both `rules` files
  are non-empty.
- **Split mechanism correctness.** niri `include` merges `binds{}` blocks by key
  (keybinds vs media use disjoint keys → lossless) and inserts window-rules
  positionally, so manifest order is fixed. Hyprland `require` gives each file a
  separate Lua scope (part-files self-contained); multiple `hl.config{}` calls
  each apply their sub-table.
- **Installer staging (`chroot.sh`).** Stage the entry file **plus** its
  `conf.d/` tree into both the niri and Hyprland curated dirs (was one
  `install -Dm644` per side). The shared `config.toml` + `noctalia-*` +
  pcmanfm-qt payload staging is unchanged.
- **Seed (`noctalia-preset.sh`).** `noctalia_preset_install` seeds the entry
  file and the whole sibling `conf.d/` tree into `/etc/skel`. The VM-only
  software-cursor override moves its append target from the seeded entry file to
  `conf.d/environment.{kdl,lua}` (branch by extension as today: niri `debug{
  disable-cursor-plane }`, Hyprland `hl.config({ cursor = { no_hardware_cursors
  = true } })`). The `cfg_src`/`cfg_dst` contract still passes the entry file;
  the preset derives the `conf.d/` source beside it.
- **Single source preserved.** The repo tree stays an ordinary stow package; the
  installer seeds a copy of it and never stows (ADR 0095). No second-authored
  copy of any file.

## Testing Decisions

Good tests here assert **external behavior at existing seams**, never the
internal file split itself. Two established seams, both reused — no new seam:

- **Adapter seam** — `.installer/tests/extras/niri-adapter.bats` and
  `hyprland-adapter.bats`. These already drive `noctalia_preset_install` against
  a fixture curated dir and assert the skel result. Update the fixtures to lay
  down a `conf.d/` tree and assert the tree (entry + representative part-files,
  e.g. `keybinds`, `environment`) is seeded to `/etc/skel`; assert the VM
  software-cursor override lands in the seeded `conf.d/environment` file, not the
  entry manifest. Prior art: the existing "seeds to skel" and "warns but does not
  abort when the curated dir is absent" tests.
- **Drift-guard seam** — `.installer/tests/config/noctalia-stow.bats`. Re-point
  the content greps (Noctalia autostart, Bibata cursor, Hyprland IPC
  launcher/lock binds) at the specific part-file now holding each construct
  (`autostart`, `environment`, `keybinds`), so a content regression still fails.
  Prior art: the existing `config.kdl`/`hyprland.lua` content assertions in the
  same file.
- **Validator gate (manual/local, not bats).** `niri validate` and `Hyprland
  --verify-config -c hyprland.lua` must both pass on the split configs — this
  catches a bad include/require path or a mis-moved construct. Run locally; not
  wired into the bats suite because niri is not present in CI.

## Out of Scope

- Any change to config *content* or behavior — bindings, rules, env, look, and
  keybind parity (ADR 0096) all stay byte-for-byte equivalent in aggregate.
- The shared `config.toml`, `noctalia-*` helpers, and pcmanfm-qt payload —
  untouched; their staging/seeding stays as-is.
- Adding new includes, monitor/output config, or any new setting.
- Wiring the compositor validators into CI (niri is not installed there).
- The `wayland_shell=none` bare path — it seeds nothing, so the split does not
  touch it.

## Further Notes

- niri `include` needs niri ≥ 25.11; the fleet pulls bare Arch `niri`, well past
  that floor. Hyprland `require` needs ≥ 0.55; the fleet is on 0.56.2.
- Manifest order matters for niri (positional window-rules, key-conflict bind
  override) and for Hyprland (later `hl.config` keys win). Keep the fixed order:
  environment, input, appearance, autostart, keybinds, media, rules.
- Follow the installer/comment-style docs: each part-file gets a compact header
  keeping the non-obvious *why* + its `(ADR NNNN)` anchor, not a restatement of
  the manifest or ADR 0107.
