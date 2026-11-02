# 13: Desktop Audit Run

**What to build:** one desktop-variant Audit Run in the VM proves every
VM-verifiable change together: the niri autostart leak gone, pcmanfm-qt
owning FileManager1, kwallet behind niri's Secret portal, oomd monitoring,
the new packages present, blueman absent. Parent: PRD.

**Blocked by:** 07, 08, 09, 10, 11, 12.

**Status:** ready-for-agent

- [ ] One VM at a time (ADR 0155); `vm-agent.sh status` first, `stop`
      after.
- [ ] Every new probe passes in its sessions.
- [ ] No new findings beyond accepted Known Noise.
- [ ] Result recorded like prior Audit Run docs.

## Comments

- 2026-11-02: Audit Run `.audit-runs/20261102-005650` (desktop, at 6f4b7c3):
  67 findings, ticket NOT done. New probes all PASS where they apply:
  autostart gates + kwallet init (niri, Umbriel), FileManager1 owned by
  pcmanfm-qt (all three), oomd, Secret portal. Open:
  - Hyprland 0.57.0: Noctalia not running → noctalia-running,
    qt-platformtheme and 33 bind findings. Prior run (0.56) passed. Cause
    unknown; truncated hyprland.log. Needs a `--keep` rerun.
  - umbriel-git r1225: `umbriel config validate` → invalid → 19 bind
    findings. Prior run passed. Likely upstream key drift; needs `--keep`.
  - wireplumber `UPower NameHasNoOwner` persists: installing upower is not
    enough (wireplumber does not activate it) — needs upower.service
    enabled (ticket 11 criterion unmet).
  - New noise from this change set: pcmanfm-qt daemon `QFont::fromString:
    Invalid description '(empty)'`; ksecretd warnings in niri (kwallet via
    the Secret portal / probe ping).
  - Likely upstream/VM: claude skill YAML warning, kitty EGL in VM,
    xdg-desktop-portal GLib type warnings, KDE notifications unit, kwin IM.
