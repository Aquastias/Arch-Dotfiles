# 03 — Remove the stale `xsettingsd.conf`

**What to build:** The stow payload ships an `xsettingsd.conf` that names a
retired theme (`Breeze`) and cursor (`breeze_cursors`) — both killed by ADR
0102/0098 — and that nothing on any compositor launches. Remove it so the repo
carries no dead config. Anchored by ADR 0104.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [x] `xsettingsd.conf` is deleted from the payload (and its now-empty directory
      not left tracked).
- [x] No installer code, adapter, or test references it; the suite stays green.

## Comments

- Done in `faadbe3`. `xsettingsd.conf` (and its empty dir) removed; no
  remaining references in installer code or tests.
