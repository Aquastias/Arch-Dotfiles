# Spec: Agent-Controllable VM + VM Agent Control CLI

Status: ready-for-agent

Anchored by **ADR 0117**. Uses the [[VM Harness]], [[VM Profile]],
[[Agent-Controllable VM]] and [[VM Agent Control]] glossary terms. Respects ADR
0069/0091 (display-manager auto-resolution), ADR 0100 (Noctalia owns lock/idle),
ADR 0116 (`inotify-tools` in the preset).

## Problem Statement

Debugging a desktop VM this repo builds means logging into a session, changing
state, screenshotting, switching to another session, and inspecting — across
niri, Hyprland and KDE on one shared `$HOME`. The [[VM Harness]] already
authorizes an SSH key and enables `sshd` on persistent debug VMs, but the guest
boots to the **sddm greeter with a manual login**, and everything else is
ad-hoc. In one live session I had to rediscover, by hand and repeatedly: switch
session by editing the sddm autologin config and rebooting; find a session's
`WAYLAND_DISPLAY`/`DBUS_SESSION_BUS_ADDRESS` from `/proc/<pid>/environ`;
screenshot with `grim` on wlroots but `spectacle` on Plasma; fight an idle lock
that covered the apps mid-task; pipe the `sudo` password; and dodge
self-matching `pgrep`. Every future debugging session would pay that cost again.

## Solution

Make every **persistent-flow** [[VM Harness]] VM an [[Agent-Controllable VM]] —
a box an AI agent can fully drive over the harness SSH key — and put the driving
logic in one host-side CLI, [[VM Agent Control]] (`vm-agent.sh`, a sibling of
`vm.sh`). The agent can log in to any session, log out, reboot, screenshot,
run/launch apps with the right session environment, and lock/unlock and
toggle idle inhibition on demand — with no per-session rediscovery. The
`--testing` cells stay out of scope. Screenshot tools are already packaged
(`grim` on wlroots, `spectacle` on KDE), so the only new surface is the CLI plus
the autologin it manages.

## User Stories

1. As a debugging agent, I want to boot a VM directly into a named session
   (niri/Hyprland/KDE) without a greeter, so that I can start work headlessly.
2. As a debugging agent, I want `session <name>` to switch the VM to another
   session (rewrite autologin + reboot + wait-until-ready), so that I can move
   between compositors and Plasma deterministically.
3. As a debugging agent, I want `logout` to end the current session and get a
   fresh one (via `loginctl terminate-session` + re-autologin), so that I can
   reset session state without a full reboot.
4. As a debugging agent, I want `reboot` to restart the VM and wait until the
   session is back, so that I can test first-login behaviour.
5. As a debugging agent, I want `ready` to block until the chosen session's
   compositor/shell is actually up, so that my next command doesn't race boot.
6. As a debugging agent, I want `shot [file]` to auto-pick the right tool by the
   running compositor (`spectacle` under Plasma, `grim` under niri/Hyprland), so
   that one command screenshots any session.
7. As a debugging agent, I want `shot` to source the session environment
   automatically and pull the PNG to the host, so that I never hand-set
   `WAYLAND_DISPLAY` or copy files.
8. As a debugging agent, I want `shot` to wake the display first and time out
   with a clear error on a render-stall, so that a slept output gives a message,
   not a hang.
9. As a debugging agent, I want `exec <cmd>` to run a command inside the guest
   with the session's environment already set, so that IPC tools (e.g.
   `noctalia msg`) and toolkit env reach the running session.
10. As a debugging agent, I want `launch <app>` to start a GUI app detached, so
    that launching it never holds my SSH channel open.
11. As a debugging agent, I want `idle off` (default) to inhibit idle/lock/DPMS
    so long operations aren't interrupted, and `idle on` to restore it, so that
    control is smooth but reversible.
12. As a debugging agent, I want `lock` and `unlock` verbs, so that I can
    exercise and debug the session lock (Noctalia's, ADR 0100) on demand.
13. As a debugging agent, I want lock/idle **never** permanently disabled in the
    guest, so that lock behaviour stays fully testable.
14. As a debugging agent, I want `ssh` to drop me into an interactive guest
    shell, so that I can poke at anything the verbs don't cover.
15. As a debugging agent, I want the CLI to use the harness SSH key and pipe the
    harness `sudo` password, so that privileged steps (autologin rewrite,
    reboot) just work.
16. As a debugging agent, I want autologin handled DM-agnostically (sddm
    `[Autologin]` when KDE is present, greetd `[initial_session]` otherwise), so
    that `session` works on combined and pure-compositor VMs alike.
17. As a debugging agent, I want the CLI to own its autologin drop-in (not mutate
    the seeded DM config), so that switching sessions is clean and reversible.
18. As a debugging agent, I want a sensible default boot session (the first
    compositor in the desktop set), so that a fresh VM lands in a useful session
    that I can override per task.
19. As a debugging agent testing Qt theming, I want to use a KDE app (Dolphin by
    default), so that Qt checks are consistent and reproducible.
20. As a debugging agent testing GTK theming, I want to use any GTK app of my
    choice (nm-connection-editor default), so that GTK checks are flexible.
21. As a debugging agent, I want the CLI to select the VM the same way `vm.sh`
    does (`--profile`/name), so that it fits the existing harness ergonomics.
22. As a debugging agent, I want the CLI's `virsh`/`ssh` calls to follow the
    sandbox retry rule (retry with the sandbox disabled on a `libvirt
    unreachable (sandbox?)` signal), so that libvirt-under-sandbox doesn't block
    me.
23. As a maintainer, I want the CLI's pure decision logic unit-tested, so that a
    wrong autologin-config or tool-selection regresses loudly in CI.
24. As an operator, I accept that a human loses the greeter session-picker on
    these VMs (autologin-by-default), so that every VM is agent-drivable.
25. As a maintainer, I want screenshot tools to keep coming from the existing
    desktop package sets (grim via niri, spectacle via KDE), so that no new
    package wiring is introduced.

## Implementation Decisions

- **New host-side CLI `vm-agent.sh`**, a sibling of `vm.sh` under the [[VM
  Harness]], taking the same profile/VM selector and driving the guest over the
  harness SSH key. Verbs: `session <niri|hyprland|kde>`, `shot [file]`,
  `exec <cmd…>`, `launch <app…>`, `logout`, `reboot`, `idle <on|off>`, `lock`,
  `unlock`, `ssh`, `ready`.
- **Scope = persistent-flow VMs only.** The `--testing` cells are excluded
  (single-shot, desktop-less, served by their sentinel/serial channel).
- **DM-agnostic autologin, on by default, CLI-owned.** The CLI writes an
  agent-owned autologin drop-in for the resolved greeter — sddm `[Autologin]`
  (KDE present) or greetd `[initial_session]` (KDE-free compositor set), per ADR
  0069/0091 — never mutating the seeded DM config. Session-switch rewrites it and
  reboots; `logout` uses `loginctl terminate-session` (fresh re-autologin). It is
  idempotent (ensures the drop-in on first use). Default boot session = the first
  compositor in the desktop set; the agent overrides per task.
- **Screenshot auto-selects by compositor.** Detect the running compositor
  (`kwin_wayland` → `spectacle`; niri/Hyprland → `grim`), source the session env
  from `/proc/<compositor-pid>/environ`, wake the display (dpms-on), capture with
  a timeout, and pull the PNG to the host. No single universal tool exists across
  wlroots and Plasma headlessly.
- **Idle/lock is a reversible, CLI-held inhibitor** (default inhibited), toggled
  by `idle on|off`, with explicit `lock`/`unlock` via `loginctl`. Nothing is
  permanently disabled in the guest — lock (ADR 0100) stays debuggable.
- **Credentials:** SSH via the harness key; `sudo` via the harness password
  (piped) — kept, not converted to passwordless sudo.
- **No new packages.** `grim` already ships via the niri package set and
  `spectacle` via KDE (plasma-meta); `inotify-tools` via the Noctalia preset (ADR
  0116). The CLI asserts/uses whichever tool matches the running compositor.
- **Pure logic is factored into testable functions** (autologin-config
  generation; compositor→tool selection; session-name→`.desktop` mapping) so the
  decision logic is unit-testable without a live VM, matching how `vm/lib`
  functions are tested today.
- **Sandbox interplay:** the CLI's `virsh`/`ssh` obey the existing
  `docs/agents/vm-sandbox.md` retry-with-sandbox-disabled rule.
- **Docs:** an agent-facing `docs/agents/vm-agent-control.md` (verbs + the
  gotchas: env from `/proc/<pid>/environ`, grim-vs-spectacle, render-stall wake,
  self-matching `pgrep`) and a one-line `CLAUDE.md` pointer, written against the
  built verbs.

## Testing Decisions

Good tests here assert **external, committed behaviour of the CLI's pure
decision logic** — not the live SSH/reboot/screenshot round-trip, which has no
place in CI (the repo has no live desktop under test; the integration path is
verified by hand on the `arch-combined` VM, exactly as the App Theming and Live
Theme Bridge work was).

- **Seam — `.installer/tests/vm/vm-agent.bats`** (new, at the highest point: the
  CLI's pure helpers), reusing the established `.installer/tests/vm/*.bats`
  pattern. Assert:
  - **Autologin-config generation** produces a correct sddm `[Autologin]` block
    (Session/User) for a KDE/combined set and a correct greetd `[initial_session]`
    for a KDE-free compositor set, for each of niri/Hyprland/KDE.
  - **Compositor → tool selection** maps a detected `kwin_wayland` to
    `spectacle` and niri/Hyprland to `grim`.
  - **Session-name → `.desktop`** mapping and the default-session (first
    compositor) resolution are correct.
  - **Verb dispatch / usage** rejects an unknown verb and prints usage.
  Prior art: `.installer/tests/vm/vm-cli.bats` and `flow-persistent.bats`, which
  unit-test the harness's own argument/flow logic without provisioning a VM.
- No test provisions or drives a live VM; the driving verbs are exercised
  manually on the persistent `arch-combined` VM at implementation time.

## Out of Scope

- **Test-flow (`--testing`) cells.** Single-shot and often desktop-less; they
  keep their sentinel/serial channel.
- **Passwordless sudo.** The operator keeps password sudo with the harness
  password.
- **Permanently disabling lock/idle** in the guest — rejected so lock/idle stay
  debuggable; only a reversible inhibitor is used.
- **Autologin on real hardware.** This is a VM-harness-only affordance; real
  installs keep the greeter.
- **A guest-side agent daemon** — session-switch/reboot cross a reboot, which the
  host must own.
- **Live-VM integration tests in CI.** Out of the repo's test model.
- **New screenshot-tool packaging** — grim/spectacle already arrive with the
  desktop sets.

## Further Notes

- The whole design is distilled from a real session that drove `arch-combined`
  end-to-end (session switching, grim/spectacle screenshots, cross-session
  theming isolation) by hand — every verb maps to a step that cost time to
  rediscover.
- `logout` semantics on a headless box: with autologin `Relogin` on, terminating
  the session yields a fresh re-autologin of the same session — a session reset
  without a reboot.
- The default boot session being a compositor (not KDE) reflects that most agent
  debugging (Noctalia, live theming) happens in the wlroots sessions; KDE is
  reached on demand with `session kde`.
