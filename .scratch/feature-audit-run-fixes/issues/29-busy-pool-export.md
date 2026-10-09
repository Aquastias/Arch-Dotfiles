# 29: rpool export stays busy at finalize

**What to build:** Finalize always exports rpool, so the first boot imports
it. In roughly 2 of 18 installs per run, `zpool export` reports "pool is
busy" and the installed system never boots ("Unable to import pool").

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Cause named from the holder log of a failing install
- [ ] Root-cause fix with a test; no busy export across a full Audit Run

## Comments

**2026-10-09 — Seen in:**
- 20261006-035943 (refind, ufw)
- 20261008-095456 (laptop)
- 20261008-191424 (efistub, ufw)

**Ruled out:**
- No process holds a file, cwd or root under the target or on a zvol.
  The holder log (fbd5fa1) was empty.
- Killing chroot leftovers (66e035c) didn't help.

**Next:**
- f901e0b also logs pool mounts held in other mount namespaces, and zvol
  kernel holders. Read the `holder:` lines of the next failing install.
- Suspects:
  - a live-ISO service namespace keeping the mounts;
  - a bind mount of a dataset subdirectory, which `zfs umount -a` won't
    remove.
