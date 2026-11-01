# 09: niri Secret portal → kwallet

**What to build:** on a KDE co-install, sandboxed apps in niri can store
secrets: the Secret portal resolves to kwallet instead of the missing
gnome-keyring. A bare niri box keeps the packaged portal config. Parent: PRD
(ADR 0162).

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The niri adapter writes a niri portals override keeping the packaged
      preferences and routing Secret to kwallet, iff `kde` is co-installed.
- [ ] Adapter bats cover both cases.
- [ ] Feature Audit probe: the Secret portal backend in niri is kwallet.
