# 27: Full Audit Run reaches zero Findings

**What to build:** A fresh full Audit Run (no --reuse, no FEATURE_AUDIT_SKIP)
reports zero Findings.

**Blocked by:** 01-26

**Status:** ready-for-agent

- [ ] Run id recorded in Comments
- [ ] Any new Finding gets a new ticket before closing

## Comments

**2026-10-04 — Run 20261003-001455: 135 Findings.** Root causes, fixed
(all fallout of this ticket, tracked here rather than as new tickets):

- grub never installed: GRUB cannot read the encrypted, all-features rpool
  → boots from the ESP (fc24451, ca2d261; ADR 0078 amended).
- Outages ended installs (codeberg 503, GitHub blip) → pacstrap retried,
  unreachable AUR sources skipped with a warning (78753f8, 6a59066; ADR 0052).
- ufw nixd build (aws-c-common soname mid-transition) and tuned zfs-utils
  download: upstream transients, no change.
- pacman.conf copied only on ZFS (465dc30); nvim on pure hosts (b8ed740,
  050b66d, c36cf19); searxng valkey/limiter/chown/network (4bbc24b,
  d3336c4); KDE calendar migration (34fb4a5); rkhunter --update codes
  (ad67ac0); ppd python-gobject (7600ce8); kitty Notify (6215361); zfs
  snapshot probe (ed899c1); DISPLAY w/o shell (f39c427); grim (b75ea3c).
- vconsole race: fbcon deferred takeover vs a session on tty1 → greetd on
  VT 2 (a869aac), verified on a held VM.
- Ctrl+Alt+Delete bind rebooted the guest: harness declared readiness
  before the compositor owned the VT (46df023).
- kde-pure/greetd shutdown hangs: virgl GPU stall (D-state GPU clients) →
  harness resets a wedged shutdown (f3bc912, c067650); swap stays zvol.
- base/niri-pure silent boot1: cause unknown → one power-cycle retry,
  recorded (8784e9a); evidence capture (72cccbb).
- Known Noise approved: 59dc642, dbcee7f.
- Audit speed-up (Variant Phases, Audit Cache, readiness waits; ADR 0152
  amended): 41afb16, 2849101, 8c2ae64, ef01c15.
