# 04: Conditional: XWayland path fix (flags, xwayland-satellite)

**What to build:** Only if ticket 01 shows an XWayland path causes the
clipboard failure: Chromium and VSCodium run natively on Wayland through
seeded, stowable Wayland platform flags, and/or niri gains
`xwayland-satellite` in its adapter core so X11 clients and their clipboard
work. Grounded in the Arch Wiki Chromium/niri pages. If 01 shows no XWayland
cause, close as `wontfix`, citing 01's evidence.

**Blocked by:** 01, 02

**Status:** ready-for-agent

- [ ] Decision (do / wontfix) stated with a reference to 01's evidence.
- [ ] If done: flags seeded to skel + stowable; guards next to the existing
      adapter/stow bats.
- [ ] If done: `xwayland-satellite` in niri core with the adapter bats
      asserting it.
- [ ] If done: vm-agent run shows cross-toolkit paste now passes on the
      affected compositor.
