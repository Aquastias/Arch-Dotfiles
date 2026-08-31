# 01 — octopi becomes KDE-only

**What to build:** `octopi` installs only when KDE is selected. Today it sits in
the shared Host Core base, so every real host (including niri-only and laptop)
pulls it; move it so a niri-only or laptop host never installs it, and a KDE host
gets it alongside the other KDE-tied AUR tools.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

Anchor: ADR 0094 (octopi rider). Mirrors the `qt6ct-kde` precedent (ADR 0087) of
a KDE-tied AUR tool living in the KDE adapter's `aur` block.

- [ ] `octopi` removed from `hosts/core/profile.jsonc` `packages.aur.misc`.
- [ ] `octopi` added to `extras/desktop/kde/install-kde.jsonc` `aur` (its own
      category, e.g. `system`), so it installs iff KDE is selected.
- [ ] `kde-adapter.bats` asserts octopi resolves under the KDE `aur` pass.
- [ ] `profiles-aur.bats` / `resolver.bats` assert octopi is absent from the core
      `aur` set (a niri-only host never pulls it).
- [ ] The full installer test suite passes.
