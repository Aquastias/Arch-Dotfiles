# 01: harden-boot aborts at install-warn-hook on systemd-boot

**What to build:** `tools/harden-boot.sh` apply on a systemd-boot host
without `/etc/default/grub` exits 1 right after "applying:
install-warn-hook": the 97-stray-kernel-warn hook is never written and
reconcile-microcode / drop-fallback never run. Cause: the selected-kernels
helper ends on `[[ -f "$ROOT/etc/default/grub" ]] && awk …`, so it returns
1 when the file is absent, and `set -e` aborts the caller. Reproduced on a
fake root at HEAD before and after readability ticket 20 (identical), so
not a refactor regression. Fix: end the helper with `return 0` (or an
`if`), and cover the apply path in harden-boot.bats.

**Blocked by:** None (can start immediately)

**Status:** needs-triage

- [ ] Selected-kernels helper returns 0 when no grub defaults file exists
- [ ] Apply on a systemd-boot fake root writes all three hooks, rc 0
- [ ] harden-boot.bats covers apply on a systemd-boot fake root
