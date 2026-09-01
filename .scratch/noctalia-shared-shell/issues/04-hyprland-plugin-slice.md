# 04 — Hyprland `hypr-*` compositor plugin slice

**What to build:** the compositor-specific widgets that work on niri via its
`niri-*` plugins also work on Hyprland via the native `hypr-*` equivalents
(workspace / animations / displays), so the *features* match on both. The
Hyprland plugin slice in `install-noctalia.jsonc` is populated and vendored on a
Hyprland install; each `hypr-*` id is verified to exist at the pinned community
ref, and any that do not exist are dropped from the slice rather than blocking
the ticket.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Each candidate `hypr-*` id is confirmed present at the pinned community ref;
      missing ones are dropped and noted.
- [ ] The `hyprland` slice in `install-noctalia.jsonc` lists the confirmed ids
      with their deps; the shared package map exposes them.
- [ ] A Hyprland install vendors the `hyprland` slice (niri still vendors the
      `niri` slice, unchanged).
- [ ] The first-login one-shot enables the vendored slice on Hyprland.
- [ ] The split stays clean: `hypr-*` are vendored/enabled only on Hyprland and
      `niri-*` only on niri; neither slice's ids appear in the shared
      `config.toml`.
- [ ] `hyprland-adapter.bats` asserts the slice is vendored; `resolver.bats`
      reports its deps.
