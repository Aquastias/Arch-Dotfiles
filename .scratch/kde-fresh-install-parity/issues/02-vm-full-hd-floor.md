# 02 — VM installs get a Full-HD floor, bare metal untouched

**What to build:** A VM install comes up at least 1920×1080 without manual
resizing, while a bare-metal install is left completely alone (no hardcoded mode,
no black-screen risk). The floor is set by appending a `video=` kernel cmdline
only when the installer detects it is running in a VM — no `kscreen`/output file
is ever seeded, so resolution stays autodetected everywhere else. (ADR 0119,
honouring ADR 0110)

**Blocked by:** None — can start immediately.

**Status:** done

- [x] The shared kernel-cmdline composition appends
      `video=Virtual-1:1920x1080` when install-time virtualization is detected
      (`systemd-detect-virt` inside the chroot).
- [x] On a bare-metal install the cmdline does NOT gain the `video=` option.
- [x] No `kscreenrc` / `kwinoutputconfig.json` or any monitor mode is seeded.
- [x] "At least" is a floor — a larger SPICE surface still scales up via
      preferred-mode autodetection.
- [x] `boot/loader-entries.bats` covers: virt-detect stubbed present → cmdline
      contains `video=Virtual-1:1920x1080`; stubbed absent → it does not.

## Comments

- 2026-09-27 doc sync: shipped in 8a32898, 54ecfba, 41a2188, 378db0b, a96edbc,
  e79ca17, 4352be4, dfc347d, 8f3795b, badf9e0, cd8f5a0, 840dfea, f598ff0 (ADR
  0118-0121).
