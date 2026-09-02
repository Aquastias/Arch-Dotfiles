# 03 — `--hold-on-fail` for the test/matrix flow

**What to build:** A failed `--testing` cell can be inspected instead of
vanishing. A new `--hold-on-fail` flag makes the disposable test flow skip its
`poweroff -f` on a non-zero result, leaving the VM up so it is reachable over
serial (the console capture channel), reusing the `===INSTALLER-EXIT-N===`
sentinel the test flow already emits and the hold-and-report behavior from
ticket 02.

Anchored by ADR 0099.

**Blocked by:** 02 — reuses the shared hold-and-report-access behavior.

**Status:** ready-for-agent

- [ ] `--hold-on-fail` on the `--testing` flow skips `poweroff -f` when the cell
      exits non-zero.
- [ ] A held test VM stays inspectable over serial.
- [ ] On a passing cell the flag is a no-op (normal poweroff).
- [ ] Seam-4 test (mocked libvirt): with `--hold-on-fail`, a non-zero cell does
      not power off; a zero cell still does.
