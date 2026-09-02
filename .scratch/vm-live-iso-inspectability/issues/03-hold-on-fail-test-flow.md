# 03 — `--hold-on-fail` for the test/matrix flow

**What to build:** A failed `--testing` cell can be inspected instead of
vanishing. A new `--hold-on-fail` flag makes the disposable test flow skip its
`poweroff -f` on a non-zero result, leaving the VM up so it is reachable over
serial (the console capture channel), reusing the `===INSTALLER-EXIT-N===`
sentinel the test flow already emits and the hold-and-report behavior from
ticket 02.

Anchored by ADR 0099.

**Blocked by:** 02 — reuses the shared hold-and-report-access behavior.

**Status:** done

- [x] `--hold-on-fail` on the `--testing` flow skips `poweroff -f` when the cell
      exits non-zero (wired in vm.sh, env>profile>flag).
- [x] A held test VM stays inspectable over serial (root autologin getty on
      ttyS0; the flow prints the `virsh console` + cleanup commands).
- [x] On a passing cell the flag is a no-op (poweroff still guarded by rc==0).
- [x] Seam test: the rendered seed guards poweroff and adds the autologin shell
      only under `--hold-on-fail`; default keeps the self-disposing poweroff.
