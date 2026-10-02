# 11: Gate bind probes on pure and no-shell

**What to build:** Bind probes skip our expectations where our
compositor/kitty config is not deployed, and Noctalia binds when
wayland_shell is none. Clears the pure/no-shell bind Findings.

**Blocked by:** 10

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] binds.bats or probe-lib bats covers both gates
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone
(niri-pure, hyprland-pure, kde-pure, no-shell)

## Comments

Bind gate: stock and shell-less niri/Hyprland skip (f6956a0).
