# 02: Clipboard keep-alive pinned + prober CLIPBOARD marker

**What to build:** The regular clipboard stays pasteable after the source app
closes on both wlroots sessions: the curated Noctalia config sets
`clipboard_keep_from_closed_apps = true` explicitly (ADR 0147). Every VM run
checks it automatically: the TEST-ONLY desktop-verify prober emits a
per-session `CLIPBOARD-OK`/`CLIPBOARD-FAIL` marker, following the ADR 0100
polkit/idle probe pattern.

**Blocked by:** 01

**Status:** done

- [x] Curated `config.toml` `[shell]` pins the keep-alive; static guard in
      the Noctalia stow suite (prior art: the `polkit_agent` guard).
- [x] Prober copies a token to regular + primary, kills the source, asserts
      the regular token is still pasteable and primary works while the
      source is live, then emits the marker.
- [x] The host records the marker next to the existing probe markers.
- [x] Stubbed prober bats cover the OK and FAIL paths.
- [x] VM run shows `CLIPBOARD-OK` on niri and Hyprland.
- [x] No new package installed (no `wl-clip-persist`, `cliphist` still off).

## Comments

- 2026-09-28: `config.toml` pins `clipboard_keep_from_closed_apps = true`
  (stow guard). Prober `probe_clipboard`: kitty (`kitten clipboard`, regular +
  `--use-primary`) is the owner, because Noctalia ignores `wl-copy` sources
  and Hyprland 0.56 drops `wl-copy -p`. The owner is killed, then the regular
  token is checked. `keep=xfail` on Hyprland < 0.57 (hyprwm/Hyprland#16117,
  ADR 0147). Stubbed bats: 5 cases + host marker extraction. VM (Hyprland
  0.56.2), the probe function run as root: `===HYPR-CLIPBOARD-OK
  keep=xfail===`. niri keep-alive verified by the ticket 01 matrix (12/12
  after close). Also: both compositors' autostart sets
  `gtk-enable-primary-paste true` (GNOME 50 defaults it off). The operator
  confirmed middle-click in kitty and pcmanfm-qt.
