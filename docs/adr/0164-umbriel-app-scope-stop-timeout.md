# ADR 0164: Umbriel app scopes stop within 5 seconds

## Status
Accepted — implemented; verified on the held desktop Audit VM.

## Context
Since upstream's session rework (umbriel PR #461), a user quit
(`session-quit` + Enter) stops `umbriel-session.target`, which waits for
every `app-umbriel-<pid>-<n>.scope` holding the compositor's launched
children before `umbriel.service` exits. Noctalia's audio-switcher plugin
polls `bluetoothctl devices`; with no bluetoothd (the Bluetooth toggle off,
or a VM) it waits for the daemon and outlives SIGTERM. The quit then hung
on systemd's default 90 s stop timeout: the confirm dialog stayed on screen
with every client gone, and the desktop Audit Run's quit binds failed
(journal: `app-umbriel-…scope: Stopping timed out. Killing. … bluetoothctl`).

## Decision
The Umbriel adapter writes a system-wide user-unit prefix drop-in,
`/etc/systemd/user/app-umbriel-.scope.d/10-stop-timeout.conf`, with
`TimeoutStopSec=5s`, so every Umbriel app scope is SIGKILLed 5 s after
SIGTERM. Verified on the held VM: with a hanging `bluetoothctl` in the
scope, quit completes in about 5 s instead of 90 s.

## Considered Options
- **Disable the audio-switcher plugin's Bluetooth polling** — rejected:
  upstream plugin code, and any other stuck child would stall quit the same
  way.
- **Lengthen the audit's 10 s session-end wait** — rejected: it hides a
  real 90 s logout stall the operator would hit with Bluetooth off.
- **A longer cap (e.g. 30 s)** — rejected: apps already lose their windows
  at quit; 5 s covers a clean SIGTERM exit.

## Consequences
- An app that needs more than 5 s to flush state on logout is killed.
- Only Umbriel's scopes are affected; Plasma, niri and Hyprland keep
  systemd's default.
