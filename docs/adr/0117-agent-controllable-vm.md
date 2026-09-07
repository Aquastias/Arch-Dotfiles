# Agent-Controllable VM + host-side VM Agent Control

---
Status: accepted. Extends the [[VM Harness]] (`.installer/vm/`) and its
persistent flow; sibling to `docs/agents/vm-sandbox.md` (libvirt-under-sandbox
retry rule). Distilled from a live debugging session that drove the running
`arch-combined` VM end-to-end (session switching, screenshots, cross-session
theming isolation) entirely by hand.
---

Debugging a running desktop VM this repo builds means logging into a session,
changing state, screenshotting, switching to another session, and inspecting —
across niri, Hyprland and KDE on one shared `$HOME`. The [[VM Harness]] already
authorizes a harness SSH key and enables `sshd` on persistent debug VMs, but the
installed guest boots to the **sddm greeter and a manual login**
(`combined.jsonc`: "Log in, then pick a session at the greeter"). Every other
control was **ad-hoc** in that session and cost real time to rediscover:

- switch session = hand-edit sddm `[Autologin] Session=` + `systemctl reboot`;
- find the session's `WAYLAND_DISPLAY`/`DBUS_SESSION_BUS_ADDRESS` from
  `/proc/<compositor-pid>/environ`;
- screenshot = `grim` on niri/Hyprland but **`spectacle` on Plasma** (no
  wlr-screencopy), and a black/hung capture whenever the display had slept;
- the idle lock fired mid-task and covered the apps (worked around with
  `caffeine`);
- `sudo -S` piping the harness password `12345`;
- self-matching `pgrep -f` false positives when the check string was in the
  driving command line.

## Decision

Make every **persistent-flow** debug VM an **[[Agent-Controllable VM]]** — a box
an AI agent can fully drive over the harness SSH key — and put the driving logic
in one host-side surface, the **[[VM Agent Control]]** CLI. The ephemeral
`--testing` cells are out of scope (single-shot, often desktop-less, already
served by their sentinel/serial channel).

1. **Host-side CLI, `.installer/vm/vm-agent.sh`** — a sibling of `vm.sh` taking
   the same `--profile`/VM selector, driving the guest over the harness key.
   Verbs: `session <niri|hyprland|kde>`, `shot [file]`, `exec <cmd…>`,
   `launch <app…>`, `logout`, `reboot`, `idle <on|off>`, `lock`, `unlock`,
   `ssh`, `ready`. Session-switch and reboot inherently cross a reboot, so they
   are host-side by nature; the guest stays stock apart from provisioning. A
   guest-side daemon and a doc-only playbook were both rejected — the former
   can't own the reboot, the latter is the exact brittleness this replaces.

2. **DM-agnostic autologin, on by default.** Provisioning turns autologin on for
   the *resolved* greeter (ADR 0069/0091): sddm `[Autologin]` when KDE is in the
   set, greetd `[initial_session]` for a KDE-free compositor set. `session <x>`
   rewrites whichever applies (an agent-owned drop-in, not the seeded DM config)
   and reboots + waits-ready; `logout` = `loginctl terminate-session` (re-
   autologins a fresh session, no full reboot); `reboot` = reboot + wait. The
   **default boot session is the first compositor** in the desktop set
   (niri→hyprland→kde) — compositor sessions are where most debugging happens;
   the agent overrides per task. **Trade-off:** a human loses the greeter's
   session-picker (they switch with `session <x>` or the drop-in) — accepted, as
   the goal is "every VM is agent-drivable."

3. **Screenshot auto-selects by compositor.** No single tool spans wlroots and
   Plasma headlessly, so `shot` detects the running compositor
   (`kwin_wayland`→`spectacle -bnf`; niri/Hyprland→`grim`), sources the session
   env from `/proc/<pid>/environ`, **wakes the display** (dpms-on) first,
   captures with a timeout, and pulls the PNG to the host — reporting clearly on
   the render-stall rather than hanging.

4. **Idle/lock is agent-controlled and reversible — never provisioned off.** The
   CLI holds a persistent, removable idle/suspend/DPMS **inhibitor**, default
   *inhibited* so long operations aren't interrupted; `idle on|off` toggles it
   and `lock`/`unlock` (via `loginctl lock-session`/`unlock-session`, proven to
   work) exercise the lock on demand. Nothing is permanently disabled, so the
   Noctalia lock (ADR 0100) and idle behaviour stay fully debuggable — the
   operator's explicit correction to an earlier "bake it off" proposal.

5. **Privilege via the existing harness credentials.** SSH is the harness key;
   privileged steps pipe the harness password **`12345`** (root and user) to
   `sudo` — kept as-is, not converted to passwordless sudo (operator's call).

6. **Guaranteed tooling on agent VMs:** `grim` on any wlroots-capable box,
   `spectacle` on any KDE box (added to the relevant adapter list if not already
   pulled in); `inotify-tools` is already in the Noctalia preset (ADR 0116).

7. **Toolkit-test convention:** Qt-toolkit checks use **a KDE app — Dolphin by
   default** (Kate/Gwenview as alternates); GTK-toolkit checks use **any GTK app,
   the agent's choice** (`nm-connection-editor` default — a stable GTK3 app).

## Considered options

- **Guest-side agent daemon** — rejected: session-switch/reboot cross a reboot,
  which a guest process cannot own; the host is the natural driver.
- **Doc-only playbook of raw commands** — rejected: it is exactly the ad-hoc
  brittleness (env discovery, tool-per-compositor, self-matching `pgrep`) this
  ADR removes.
- **Passwordless sudo on agent VMs** — proposed, but the operator chose to keep
  password sudo with the known `12345`.
- **Permanently disabling lock/idle in the guest** — rejected: it would make the
  session lock (ADR 0100) impossible to debug; a reversible inhibitor is used.
- **Gating agent-mode behind a flag** — rejected: "every VM from now on" means
  always-on for the persistent flow.
- **A single universal screenshot tool** — none works across wlroots + Plasma
  headlessly; detection is the answer.

## Consequences

- Every persistent debug VM is agent-drivable out of the box: log in, switch
  session, screenshot, exec, lock/unlock, reboot — one CLI, no rediscovery.
- A human loses the greeter session-picker on these VMs (autologin-by-default);
  they use `vm-agent.sh session <x>`.
- Lock and idle remain fully testable on demand (reversible inhibitor).
- New harness surface: the `vm-agent.sh` CLI, the DM-agnostic autologin
  provisioning, and the guaranteed screenshot tooling — plus an agent-facing
  `docs/agents/vm-agent-control.md` (verbs + the gotchas above) and a `CLAUDE.md`
  pointer, both landing with the CLI implementation.
- Cross-references `docs/agents/vm-sandbox.md`: `vm-agent.sh` runs `virsh`/`ssh`
  that the command sandbox often blocks, so the same "retry with the sandbox
  disabled on a `libvirt unreachable (sandbox?)` signal" rule applies.
