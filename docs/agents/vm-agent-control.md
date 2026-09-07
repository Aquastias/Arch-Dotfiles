# Driving a debug VM: VM Agent Control

`.installer/vm/vm-agent.sh` drives a persistent [[Agent-Controllable VM]] over
the harness SSH key (ADR 0117): log in to any session, log out, reboot,
screenshot, run/launch apps in the live session, and lock/unlock. Use it instead
of hand-rolling `virsh`/`ssh`/`grim` — it encodes every gotcha below.

## Invocation

```
.installer/vm/vm-agent.sh [--profile <cat>/<name> | --vm <name>] <verb> [args…]
```

`--profile` defaults to `desktop/combined` (→ the `arch-combined` VM). Selects
the VM exactly like `vm.sh`. The VM must be running.

| Verb | Does |
|------|------|
| `ready [timeout]` | block until the session's compositor is up |
| `exec <cmd…>` | run a command in the guest with the live session env sourced |
| `launch <app…>` | launch a GUI app detached (returns immediately) |
| `ssh [cmd…]` | interactive guest shell (or a one-off command) |
| `session <niri\|hyprland\|kde>` | switch autologin session + reboot + wait |
| `logout` | terminate the graphical session (fresh re-autologin) |
| `reboot` | reboot + wait-ready |
| `idle <on\|off>` | toggle a reversible idle/suspend/DPMS inhibitor |
| `lock` / `unlock` | `loginctl` lock / unlock the session |
| `shot [file]` | screenshot (grim on wlroots, spectacle on KDE) → host |

Example: `vm-agent.sh session kde && vm-agent.sh shot /tmp/kde.png`.

## Gotchas it handles (and you must remember when going raw)

- **Sandbox:** its `virsh`/`ssh` hit the libvirt socket the command sandbox
  blocks. On `libvirt unreachable (sandbox?)`, retry with the sandbox disabled
  (`docs/agents/vm-sandbox.md`).
- **Session env:** `exec`/`launch`/`shot` source `WAYLAND_DISPLAY`,
  `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, etc. from a session **client**
  (noctalia/plasmashell), NOT the compositor *server* — a server has no
  `WAYLAND_DISPLAY` of its own. Without this, `noctalia msg` says "not running"
  and `grim` says "failed to create display".
- **Screenshots:** `shot` auto-picks `grim` (niri/Hyprland) or `spectacle` (KDE)
  by the running compositor. A capture on an **idle/slept headless output is
  blank/black** — the output must be actively rendering. A fresh `session`/
  `reboot` gives an active output; on a stale one, `launch` an app (or expect a
  near-empty PNG). `shot` does `dpms-on` + a timeout so a stalled render errors
  instead of hanging.
- **Session switch:** writes a CLI-owned autologin drop-in and reboots. On sddm
  it is `zz-agent-autologin.conf` — named to sort **last** in `/etc/sddm.conf.d`
  so it beats the seeded `kde_settings.conf` (sddm merges alphabetically,
  last-wins, and `kde_settings.conf` sorts after `99-*`). On greetd it rewrites
  `[initial_session]`.
- **Logout:** terminates only the **seat0** graphical session — never the
  agent's own SSH session (which has no seat). `terminate-user` would kill your
  SSH connection and hang.
- **`pgrep -f` self-match:** checking for a process from a command whose own
  cmdline contains the search string makes `pgrep -f` match *itself* — a false
  positive. Use `pgrep -x <name>` or a path-anchored pattern
  (`pgrep -f '/noctalia-theme-bridge'`).
- **sudo:** privileged steps pipe the harness password (default `12345`,
  override `VM_AGENT_SUDO_PW`) to `sudo -S` from the host, not the remote argv.

## Toolkit-test convention (ADR 0117)

When testing app theming: **Qt → a KDE app, default Dolphin** (Kate/Gwenview as
alternates); **GTK → any GTK app, your choice** (`nm-connection-editor` is a
reliable GTK3 default). This keeps Qt checks reproducible and gives GTK checks
flexibility.
