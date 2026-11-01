# 07: Suppress KDE autostarts in niri

**What to build:** on a KDE co-install, logging into niri no longer starts
kalendarac (and akonadi), the kdeconnect daemon, nm-applet or the Discover
notifier; Plasma still starts them. `pam_kwallet_init`, at-spi and
`xdg-user-dirs` keep running in niri. A bare niri box gets nothing written.
Parent: PRD (ADR 0162).

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The niri Desktop Environment Adapter writes one systemd user drop-in
      per blocklisted autostart id, conditioned on the session not being
      niri; the blocklist is one list.
- [ ] Exact ids confirmed from a desktop VM's autostart dir.
- [ ] Adapter bats: drop-ins written iff `kde` is in the desktop set.
- [ ] Feature Audit probe: none of the blocklisted processes run in the
      niri session; `pam_kwallet_init` still ran.
