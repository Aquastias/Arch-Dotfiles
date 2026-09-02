# 02 — Exit sentinel + hold-and-report on failure (persistent flow)

**What to build:** When a persistent-flow install fails, the harness tells the
user exactly how to get in and leaves the VM running. The typed installer
payload emits an explicit exit sentinel (marker file + serial line) on **both**
success and failure, mirroring the `--testing` flow's `===INSTALLER-EXIT-N===`.
The harness detects a failed install from that sentinel, prints both access
commands (the `ssh -i … <user>@<ip>` line and the `virsh console` line), and
**holds the VM powered on** instead of blocking on a poweroff that never comes.
A failed VM is never auto-destroyed; the harness prints a one-line
`virsh destroy/undefine` cleanup command (the existing `--recreate` still
works).

Anchored by ADR 0099.

**Blocked by:** 01 — the printed access commands reference the channels seeded
at boot.

**Status:** done

- [x] Typed payload emits an exit sentinel on both success and failure.
- [x] Harness distinguishes a failed install from one still running via the
      sentinel, and does not hang waiting for a poweroff on failure.
- [x] On failure the harness prints the SSH command and the `virsh console`
      command, and leaves the VM powered on.
- [x] A failed VM is never auto-destroyed; a one-line cleanup command is
      printed.
- [x] Seam-2 test: the sentinel watcher reports failure with a distinct exit
      status (not a hang/timeout) — already covered in sentinel-watcher.bats.
- [x] Seam-4 test: the payload's sentinel/hold-on-failure and the failure
      reporter are asserted; full flow_run integration stays CI/local (no VM).
