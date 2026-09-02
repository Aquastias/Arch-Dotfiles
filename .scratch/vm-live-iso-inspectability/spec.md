# Spec: VM live-ISO inspectability on installer failure

Status: ready-for-agent

Anchored by ADR 0099 (VM inspectability seeded at boot, not by the installer
payload).

## Problem Statement

I create VMs from the VM Harness to log into an environment with a system the
installer built, so I can poke at it interactively. Sometimes the install
**errors out**. When it does, I (or an agent acting for me) am left blind:

- The persistent flow authorizes the harness SSH key *inside* the typed
  `curl|bash` installer payload, so any failure **before** that step — the ISO
  not booting, tty1 autologin not settling, no network, `curl`/HTTP to the
  harness failing — leaves the VM with **no SSH key at all**. I cannot get in.
- The install log is written to a file and deliberately **never streamed to
  serial** (a slow serial reader wedges pacman), so an agent watching
  `virsh console` sees only a login prompt, not the failure.
- On failure the VM stays up but it is unclear the harness ever surfaces *how*
  to get in, and it can block waiting for a poweroff that never comes.

The net effect: exactly in the failure case I most need to inspect, the VM is
the hardest to inspect.

## Solution

Make live-ISO inspectability a property of **booting the VM**, not of the
installer running. Because a failed install has no installed system, inspection
happens in the live ISO — so the live ISO must always offer two channels, seeded
independently of the installer payload:

- **Serial** — a root **autologin getty on `ttyS0`**, driveable over
  `virsh console` with no network at all (survives no-DHCP, no-sshd, kernel
  panic). The install log stays a file; the agent reads it on demand through
  this shell.
- **Live-ISO SSH** — the harness key authorized and sshd ensured at **first
  boot** via a minimal cloud-init NoCloud seed (no install runcmd), so SSH is up
  even when the typed installer payload never executes.

On failure the harness prints both access commands and **holds the VM up**
instead of blocking. A system that installed but won't boot is covered by
routing the installed kernel to serial and a rescue hatch. Every VM created from
now on gets this, always-on, and the harness never launches so many VMs that it
crashes the host.

## User Stories

1. As a VM user, I want the live ISO to accept my harness SSH key the moment it
   boots, so that a failure *before* the installer runs does not lock me out.
2. As a VM user, I want SSH into the live ISO to work even when the installer
   payload never executes (no network, `curl` failed, HTTP unreachable), so that
   the access channel does not die with the thing that failed.
3. As an inspecting agent, I want a root autologin shell on `ttyS0`, so that I
   can drive the live environment over `virsh console` with zero network.
4. As an inspecting agent, I want to `cat` the install log from that serial
   shell, so that I can read the failure without needing SSH or network.
5. As a VM user, I do not want the install log streamed to serial, so that a
   slow reader never wedges pacman mid-install (the existing file behavior
   stays).
6. As a VM user, I want the persistent installer payload to emit an explicit
   exit sentinel on both success and failure, so that the harness can tell a
   failed install apart from one still running.
7. As a VM user, I want the harness to print the exact SSH command and the
   `virsh console` command when the install fails, so that I know both ways in.
8. As a VM user, I want a failed persistent VM to stay powered on, so that the
   evidence I need to inspect is not destroyed.
9. As a VM user, I do not want the harness to block waiting for a poweroff that
   never comes on failure, so that it returns control and tells me how to get
   in.
10. As a test-harness user, I want a `--hold-on-fail` for the `--testing` flow,
    so that a failed matrix cell stays inspectable instead of being powered off.
11. As a VM user whose system installed but won't boot, I want the installed
    system's kernel output and LUKS-unlock prompt on `ttyS0`, so that a broken
    boot is never silent.
12. As a VM user whose booted system is broken but reachable, I want it to keep
    the harness SSH key, so that I can still SSH into it (unchanged behavior).
13. As a VM user, I want a `--rescue`/`--reattach-iso` option that re-inserts
    the install ISO, so that I can boot back into the live ISO and inspect a
    half-installed pool.
14. As a rescuing agent, I want to `zpool import` the half-installed pool from
    the rescued live ISO, so that I can inspect what the installer left behind.
15. As a host operator, I want the harness to cap how many VMs run at once, so
    that it never exhausts RAM and crashes my host.
16. As a host operator, I want graphical/desktop-verify/persistent VMs forced to
    run serially, so that heavy VMs never stack up.
17. As a host operator, I want a preflight to refuse launching a VM when
    projected RAM would exceed a safe fraction of host RAM, so that I get a clear
    stop instead of a crash.
18. As an inspecting agent under a sandbox, I want a recognizable "libvirt
    unreachable (sandbox?)" signal from `vm.sh`, so that I know to retry the
    command with the sandbox disabled.
19. As a maintainer, I want these guarantees wired strictly into the VM-harness
    path, so that a real-hardware install is unaffected and keeps
    `options.ssh.enabled` as its only knob.
20. As a VM user, I want a failed VM never auto-destroyed, so that a TTL reaper
    can't delete the evidence mid-inspection.
21. As a VM user, I want cleanup of a held VM to be a printed one-line command
    (or the existing `--recreate`), so that orphans are trivial to clear when I
    am done.

## Implementation Decisions

- **Two always-on channels, seeded at boot** (ADR 0099). The persistent flow
  stops relying on the typed `curl|bash` payload for the SSH key.
  - **Serial:** the live ISO gets a **root autologin getty on `ttyS0`**. The
    install log stays a file (never streamed) — the pacman-wedge constraint is
    preserved.
  - **SSH:** give the persistent flow a minimal **cloud-init NoCloud seed** built
    by the existing seed generator, whose `user-data` authorizes the harness key
    and ensures sshd, with **no install runcmd**. The installer is still typed
    via `curl|bash`; only key authorization moves out of it.
- **Exit sentinel for the persistent flow.** The rendered installer payload emits
  an explicit sentinel (marker file + serial line) on **both** success and
  failure, mirroring the `--testing` flow's `===INSTALLER-EXIT-N===`. The harness
  detects a failed install from it, prints the SSH + `virsh console` access
  commands, and leaves the VM running rather than waiting on a poweroff.
- **`--hold-on-fail` for the test flow.** On a non-zero cell, skip the
  `poweroff -f` so the disposable VM stays inspectable, reusing the sentinel it
  already emits.
- **Broken installed system.** Append `console=ttyS0,115200` to the installed
  system's systemd-boot and GRUB loader entries for the persistent flow too
  (the mechanism already exists for boot-verify). Add a
  `--rescue`/`--reattach-iso` path that re-inserts the install ISO so the next
  boot lands on the live ISO (with the channels above), from which the
  half-installed pool can be `zpool import`ed. A booted-but-broken installed
  system keeps its harness SSH key (already true).
- **Host-safety concurrency cap.** A **pure function** maps `(free_ram, cores)`
  to a max-concurrent-VMs cap (~4 GB/VM budget, clamped to a conservative
  default). Graphical/desktop-verify/persistent VMs are forced **serial**
  regardless. A launch preflight refuses to start a VM when projected RAM would
  exceed a safe fraction of host RAM, with a clear message.
- **Lifecycle.** Failed VMs are **never** auto-destroyed (no TTL). Cleanup is a
  printed one-line `virsh destroy/undefine` plus the existing `--recreate`.
- **Sandbox fallback is an agent rule, not script logic.** `vm.sh` preflight
  emits a recognizable "libvirt unreachable (sandbox?)" signal distinguishing a
  blocked socket from libvirt genuinely down. The operating rule — *retry the
  same command with the sandbox disabled when libvirt is unreachable under
  sandbox* — is documented under `docs/agents/` and referenced from `CLAUDE.md`
  (a script cannot disable its caller's sandbox).
- **Guardrail.** All of the above is VM-harness-side only. No change to
  installer-produced config semantics; a real install keeps
  `options.ssh.enabled` as the only SSH knob.

## Testing Decisions

Good tests here assert **external behavior at the generation/decision seams**,
not internal wiring, and run **headless** — an actually-booted VM proving the
channels work end-to-end stays a CI/local manual check (consistent with how
desktop-verify is handled; the VM cannot boot in this environment).

- **Seam 1 — seed/script generation (primary, pure text; existing bats prior
  art for the seed generator and payload renderer).** Assert:
  - the persistent-flow cloud-init seed contains key-authorize + sshd-ensure +
    `ttyS0` root autologin, and **no install runcmd**;
  - the rendered installer payload emits the exit sentinel on **both** success
    and failure paths;
  - the installed loader entries (systemd-boot + GRUB) carry
    `console=ttyS0,115200` for the persistent flow.
- **Seam 2 — sentinel watcher (existing seam/bats).** Feed a serial log with a
  failure sentinel; assert it reports failure with a distinct exit status, not a
  hang/timeout.
- **Seam 3 — concurrency cap (new, small, pure fn).** Table-test
  `(free_ram, cores) → cap` with injected values; assert the serial-forcing rule
  for graphical/persistent profiles and the preflight refusal threshold. No real
  host probing in the test.
- **Seam 4 — flow-module behavior (existing mocked-libvirt harness; tests set
  `virsh`/globals to temp paths).** Assert: on failure the flow holds the VM and
  prints both access commands; `--hold-on-fail` skips `poweroff -f`; `--rescue`
  re-attaches the ISO. No real libvirt domain.

Only test external behavior: e.g. assert *what the generated seed guarantees*
(SSH/serial come up independent of the payload), not the exact templating
internals.

## Out of Scope

- End-to-end proof that SSH/serial actually work inside a booted VM — remains a
  CI/local manual verification; the VM cannot boot in this environment.
- Any change to installer-produced config or to real-hardware install behavior
  (`options.ssh.enabled` stays the only SSH knob there).
- Streaming the install log to serial (explicitly rejected — pacman-wedge).
- Secure-erase, graphical-console automation, or new inspection channels beyond
  serial + SSH.
- Auto-reaping / TTL destruction of failed VMs.
- Whether the persistent encrypted flow needs a Console Answerer for a serial
  LUKS prompt (see Further Notes — deferred, decide at build time).

## Further Notes

- Deferred, decidable at build time: the exact per-VM RAM budget and the "safe
  fraction" of host RAM for the preflight (starting points: 4 GB/VM, 80%).
- Deferred: an encrypted **persistent** VM may need a serial LUKS Console
  Answerer for a `--rescue` boot into an encrypted installed system; the test
  flow already has one to model it on.
- Next step after this spec: break into issues via `/to-issues`, sliced along the
  four seams (seed/script generation, sentinel + hold-on-fail, concurrency cap,
  rescue path + docs).
