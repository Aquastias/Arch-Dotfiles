# 02: Clipboard keep-alive pinned + prober CLIPBOARD marker

**What to build:** The regular clipboard stays pasteable after the source app
closes on both wlroots sessions: the curated Noctalia config sets
`clipboard_keep_from_closed_apps = true` explicitly (ADR 0147). Every VM run
checks it automatically: the TEST-ONLY desktop-verify prober emits a
per-session `CLIPBOARD-OK`/`CLIPBOARD-FAIL` marker, following the ADR 0100
polkit/idle probe pattern.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Curated `config.toml` `[shell]` pins the keep-alive; static guard in
      the Noctalia stow suite (prior art: the `polkit_agent` guard).
- [ ] Prober copies a token to regular + primary, kills the source, asserts
      the regular token is still pasteable and primary works while the
      source is live, then emits the marker.
- [ ] The host records the marker next to the existing probe markers.
- [ ] Stubbed prober bats cover the OK and FAIL paths.
- [ ] VM run shows `CLIPBOARD-OK` on niri and Hyprland.
- [ ] No new package installed (no `wl-clip-persist`, `cliphist` still off).
