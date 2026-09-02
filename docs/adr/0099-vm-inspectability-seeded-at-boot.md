# VM inspectability seeded at boot, not by the installer payload

Every harness VM must stay inspectable **when the installer errors out** —
and because a failed install has no installed system yet, that inspection
happens in the **live ISO**, not the target. Today the persistent flow
authorizes the harness SSH key *inside* the typed `curl|bash` installer
payload (`flow-persistent.sh:99-100`) and never streams the install log to
serial (a file, on purpose, to avoid a slow reader wedging pacman —
`flow-persistent.sh:127-130`), so any failure *upstream* of the authorize
step (no boot, no tty1 autologin, no network, `curl`/HTTP fails) leaves the
VM with **no SSH key and nothing on serial** — exactly the case that was
un-debuggable. We move the guarantees out of the payload and into VM boot:
two always-on channels, seeded by booting, not by the installer running.

- **Serial** — a root **autologin getty on `ttyS0`**, the zero-network,
  survives-panic fallback an agent drives over `virsh console` with no
  network at all. The install log stays a file, read on demand — never
  streamed.
- **Live-ISO SSH** — the harness key is authorized + sshd ensured at first
  boot via a minimal **cloud-init NoCloud seed with no install runcmd**
  (reusing `seed-generator.sh`); the installer is still typed via
  `curl|bash`, but SSH now holds even if that payload never executes.

The persistent flow gains an explicit **exit sentinel** (marker file +
serial line) on success *and* failure; on non-zero the harness prints both
access commands and **holds the VM up** instead of blocking on a poweroff
that never comes. A broken *installed* system (install succeeded, won't
boot) is covered by adding `console=ttyS0,115200` to its systemd-boot +
GRUB entries (reusing `seed-generator.sh:181-201`) plus a
`--rescue`/`--reattach-iso` hatch that re-inserts the ISO to boot the live
environment and `zpool import` the half-installed pool.

## Considered Options

- **Keep authorizing SSH in the installer payload** — the status quo.
  Rejected: it is the exact gap being fixed — the channel dies with the
  payload it lives in.
- **Stream the install log to serial** so a console watcher always sees the
  failure. Rejected: a slow serial reader wedges pacman
  (`flow-persistent.sh:127-130`); the log stays a file and the agent reads
  it over the now-guaranteed serial shell or SSH.
- **Inject the key via kernel cmdline or a staged systemd unit** instead of
  cloud-init. Rejected: the seed builder is already battle-tested and the
  NoCloud datasource is already consumed on the ISO — a no-runcmd seed is
  the smallest new surface.
- **Auto-destroy failed VMs on a TTL** to prevent orphans. Rejected: a
  failed VM *is* the evidence to inspect; reaping mid-inspection is the
  opposite of the goal. Cleanup is a printed one-liner + existing
  `--recreate`.
- **Graphical console as the agent channel** (Q2 case b). Rejected: worst
  channel for an agent (screenshots/keystrokes); serial + SSH dominate it.

## Consequences

- Scope is strictly **VM-harness-side**: no change to installer-produced
  config semantics; a real-hardware install is unaffected and keeps
  `options.ssh.enabled` as its only knob. The always-on SSH + serial
  autologin are acceptable only because these VMs are ephemeral and behind
  libvirt NAT.
- The `--testing` flow gains `--hold-on-fail` (skip the `poweroff -f` on a
  non-zero cell) so a failed matrix cell is inspectable the same way,
  reusing the sentinel it already emits.
- Host safety: VM launches enforce a **concurrency cap** derived from free
  RAM (~4 GB/VM budget) and cores, clamped to a conservative default, with
  graphical/desktop-verify/persistent VMs forced serial; a preflight
  refuses to launch when projected RAM would exceed a safe host fraction.
- Sandbox: `vm.sh` preflight emits a recognizable "libvirt unreachable
  (sandbox?)" signal; the agent-side rule to retry with the sandbox
  disabled lives in `docs/agents/` (a script cannot disable its caller's
  sandbox).
