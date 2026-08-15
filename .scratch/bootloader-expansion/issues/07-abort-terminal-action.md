# 07 — Abort terminal action

**What to build:** Give the Guided Installer an explicit way to walk away without
installing. Add an **Abort** action row alongside the existing Proceed / Save /
Export terminal actions, routing to the same clean cancel path Esc already
triggers, so `guided_build` returns the cancel result and `install.sh` skips the
back-end. Abort is pre-destructive only — it fires before any disk is touched, so
there is nothing to roll back — and the outcome is indistinguishable from never
having started the installer.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The Guided Installer shows an **Abort** action row beside Proceed / Save /
      Export.
- [ ] Selecting Abort exits the menu cleanly and makes `install.sh` skip the
      back-end, leaving disks untouched.
- [ ] Abort routes through the existing Esc cancel path (no new destructive or
      rollback logic).
- [ ] `guided-controller` / `guided-menu` tests assert the Abort row is emitted
      and maps to the cancel directive.
