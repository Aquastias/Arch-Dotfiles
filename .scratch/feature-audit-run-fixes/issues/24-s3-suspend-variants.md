# 24: S3 suspend on greetd/services-off/ufw

**What to build:** Diagnose why these variants never reach S3 while base
does; fix or explain. Fixes F984.

**Blocked by:** 06

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Root cause noted in Comments
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (greetd,
services-off, ufw)

## Comments

Power phase moved last: S3 can wedge Xwayland/seatd under QEMU virtio-gpu and
hang later reboots (e714e63). greetd/services-off S3 to be re-judged in this
run.
