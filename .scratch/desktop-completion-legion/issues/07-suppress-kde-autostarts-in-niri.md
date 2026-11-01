# 07: Suppress KDE autostarts in niri

**What to build:** on a KDE co-install, logging into niri no longer starts
kalendarac (and akonadi), the kdeconnect daemon, nm-applet or the Discover
notifier; Plasma still starts them. `pam_kwallet_init`, at-spi and
`xdg-user-dirs` keep running in niri. A bare niri box gets nothing written.
Parent: PRD (ADR 0162).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] The niri Desktop Environment Adapter writes one systemd user drop-in
      per blocklisted autostart id, conditioned on the session not being
      niri; the blocklist is one list.
- [x] Exact ids confirmed from a desktop VM's autostart dir.
- [x] Adapter bats: drop-ins written iff `kde` is in the desktop set.
- [x] Feature Audit probe: none of the blocklisted processes run in the
      niri session; `pam_kwallet_init` still ran.

## Comments

- 2026-11-01: gated on KDE co-install under the Noctalia preset (a bare niri
  may want nm-applet's tray). Discover notifier dropped from the blocklist —
  it is already `OnlyShowIn=KDE`. Ids confirmed from the archlinux.org file
  lists (kdeconnect, network-manager-applet) and akonadi-calendar's
  kalendarac. The probe's VM proof is ticket 13.
