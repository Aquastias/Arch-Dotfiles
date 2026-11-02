# 09: niri Secret portal → kwallet

**What to build:** on a KDE co-install, sandboxed apps in niri can store
secrets: the Secret portal resolves to kwallet instead of the missing
gnome-keyring. A bare niri box keeps the packaged portal config. Parent: PRD
(ADR 0162).

**Blocked by:** None (can start immediately).

**Status:** wontfix

- [x] The niri adapter writes a niri portals override keeping the packaged
      preferences and routing Secret to kwallet, iff `kde` is co-installed.
- [x] Adapter bats cover both cases.
- [x] Feature Audit probe: the Secret portal backend in niri is kwallet.

## Comments

- 2026-11-02: reverted (operator decision). The kwallet routing made
  xdg-desktop-portal activate ksecretd at every niri login, popping KDE
  Wallet's "create a new wallet 'Default keyring'" dialog (seen on the held
  audit VM). niri keeps its packaged portals config; ADR 0162 amended.
