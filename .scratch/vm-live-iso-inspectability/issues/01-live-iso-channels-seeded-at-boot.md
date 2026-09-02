# 01 — Live-ISO inspection channels seeded at boot (persistent flow)

**What to build:** Booting a persistent-flow VM makes the live ISO
inspectable **before and independently of** the installer running. At first
boot the live ISO comes up with a **root autologin getty on `ttyS0`** and the
harness SSH key already authorized, so a failure upstream of the typed
installer payload (ISO not booting past login, no network, `curl`/HTTP to the
harness failing) no longer locks the user out of either channel. The key
authorization moves out of the typed `curl|bash` payload into a minimal
cloud-init NoCloud seed (built by the existing seed generator) that carries
**no install runcmd** — the installer is still typed as before. The install
log stays a file, never streamed to serial (the pacman-wedge constraint
holds).

Anchored by ADR 0099.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Persistent-flow VM gets a cloud-init NoCloud seed whose `user-data`
      authorizes the harness key and ensures sshd at first boot, with no
      install runcmd.
- [ ] Live ISO exposes a root autologin shell on `ttyS0`.
- [ ] Harness SSH key authorization is removed from the typed `curl|bash`
      payload (it now comes from the seed).
- [ ] SSH into the live ISO works even when the typed payload never executes.
- [ ] Install log remains a file; nothing streams it to serial.
- [ ] No change to installer-produced config semantics; a real install still
      uses `options.ssh.enabled` as its only SSH knob.
- [ ] Seam-1 tests assert the generated seed contains key-authorize +
      sshd-ensure + `ttyS0` autologin and **no** install runcmd.
