# Compositor resolution/refresh is autodetected, never seeded

---
Status: accepted. Records why the operator's "4K @ 144 Hz" request seeds **no**
resolution into the niri/Hyprland configs. Reaffirms the "output is
host-specific, kept out of the portable config" invariant behind ADR 0090's niri
adapter and ADR 0096's shared keybinds; the seeded `hyprland.lua` (ADR 0105) and
niri `config.kdl` (ADR 0094/0095) already ship autodetecting output.
---

The operator asked for the desktop to come up at their monitor's native
resolution and refresh — a 3840×2160 panel that advertises 48–144 Hz (EDID range
limit; the preferred detailed timing is 4K @ 60 Hz). The obvious reading —
"hardcode `3840x2160@144`" — was rejected: a monitor mode is
**machine-physical** (EDID-keyed), exactly like the disk device paths the
installer refuses to commit (ADR 0036 in spirit). A hardcoded mode is dead
weight on every other box and **black-screens** any monitor that cannot drive
it, defeating the fresh-install guarantee the seeded configs exist to provide.

Both wlroots compositors already resolve the right mode themselves. The seeded
`~/.config/hypr/conf.d/environment.lua` sets
`hl.monitor({ output = "", mode = "preferred", … })`, and the seeded niri
`config.kdl` **deliberately omits** any `output` block (an explicit
`// No output block on purpose` note in `conf.d/input.kdl`). Both therefore pick
the monitor's **preferred** mode at first launch on whatever hardware boots
them.

## Decision

**Seed no resolution or refresh rate.** Leave niri and Hyprland on
preferred-mode autodetection — the state the configs are already in — so each
monitor comes up at its own native resolution and refresh with zero
host-specific config. KDE is symmetric: kscreen autodetects at first login (its
per-output config is EDID-hash-keyed and cannot be portably seeded — see ADR
0088's seed scope), which is why the KDE settings capture excludes `kscreenrc` /
`kwinoutputconfig.json`.

The operator's specific panel drives 4K @ 144 Hz where the EDID exposes that
mode; where it exposes only 4K @ 60 Hz, autodetection lands 4K @ 60 and the
operator raises refresh once in System Settings / a per-host `output` override.
"Whatever the hardware advertises, unattended" is the accepted contract.

## Considered options

- **Hardcode `3840x2160@144`** in both configs — rejected: host-specific, dead
  on other hardware, black-screens a mismatched monitor. This is the option the
  ADR exists to reject.
- **Hyprland `mode = "highrr"`** (highest refresh) instead of `preferred` —
  rejected: `highrr` maximises refresh *regardless of resolution*, so a monitor
  whose highest-refresh mode is a low resolution comes up downscaled; and niri
  has no equivalent keyword, so the two compositors would diverge. `preferred`
  keeps them symmetric and never sacrifices resolution.
- **A per-host `output`/`monitor` override** committed in a host profile — still
  available to anyone who wants a pinned mode; it just does not belong in the
  shared, portable seed.

## Consequences

- The seed stays portable — the same niri/Hyprland config is correct on a laptop
  panel, a VM's SPICE surface, and the 4K/144 desktop, with no black-screen
  risk.
- The operator does not get a *guaranteed* 144 Hz from the seed alone when the
  EDID's preferred timing is 60 Hz; raising it is a one-time per-host action —
  not a fleet default. Documented cost of refusing host-specific config.
- No new package, service, or code path — the decision is to **keep** the
  current autodetecting configs and to not add a resolution seed that was
  otherwise implied by the request.
