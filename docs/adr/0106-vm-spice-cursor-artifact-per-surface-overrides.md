# VM-only SPICE ghost-cursor: per-surface software-cursor overrides

---
Status: accepted. Completes the VM cursor-artifact handling begun for the
compositors (niri `debug { disable-cursor-plane }`, Hyprland
`cursor { no_hardware_cursors }`) by adding the missing Xorg/SDDM surface.
All overrides are machine-TYPE gated (`systemd-detect-virt --vm`), so real
hardware is untouched.
---

In a SPICE guest (the `vm.sh` libvirt/QEMU harness, `virtio-vga-gl` +virgl),
whenever the guest programs the **virtio-gpu hardware cursor plane**, the SPICE
client draws that cursor **itself**, client-side. With no cursor image set it
renders the default black **"X"** — a stale overlay that tracks nothing and, once
drawn, **persists** (SPICE never receives a "hide cursor", so it survives VT
switches, logout, and even into a later software-cursor session). On real
hardware there is no SPICE and no such overlay, so this is purely a VM display
artifact — cosmetic, never present on a live machine.

Each thing that can touch that cursor plane needs its own opt-out, and they live
in different config languages:

- **niri** — `debug { disable-cursor-plane }` (renders the cursor into the
  framebuffer instead of the plane).
- **Hyprland** — `hl.config({ cursor = { no_hardware_cursors = true } })`
  (Lua, ADR 0105; was `cursor { no_hardware_cursors }` under the old `.conf`).
- **SDDM's Xorg greeter** — `Option "SWcursor" "true"` on the `modesetting`
  driver, via `/etc/X11/xorg.conf.d/10-vm-sw-cursor.conf`.

The first two are seeded by the Noctalia preset; this ADR adds the third.

## Why the SDDM surface was the stubborn one

A niri/Hyprland-only VM uses **greetd**, a TTY greeter that never starts Xorg,
so nothing but the (already-overridden) compositor touches the plane — clean.
A **KDE co-install** uses **SDDM**, which runs an **Xorg greeter** on its own VT
and keeps it alive *alongside* the Wayland session. That greeter Xorg programs
the virtio cursor plane at startup, SPICE draws the X, and it lingers into the
niri/Hyprland session on the same box — the identical compositor config that is
clean on a greetd host shows the X here. So the fix belongs with **SDDM** (the
only reason Xorg runs in these VMs), gated on machine type, in the SDDM adapter.

## Decision

In `extras/dm/sddm/sddm.sh`, when `systemd-detect-virt --vm` succeeds, write the
`modesetting` `SWcursor` drop-in so the greeter Xorg renders a software cursor
from the first frame. greetd hosts never reach this code; bare-metal KDE skips
it (real HW cursor kept).

## Considered options

- **`KWIN_FORCE_SW_CURSOR=1`.** The KWin analogue — correct for a *Plasma-Wayland
  session or a KWin greeter*, but SDDM here runs an **Xorg** greeter, which KWin
  env never touches. `SWcursor` is the Xorg-level equivalent. (If a Plasma
  session is later the reported offender, `KWIN_FORCE_SW_CURSOR` is the additive
  fix for that surface — this ADR does not preclude it.)
- **Mid-session apply.** Writing the drop-in into a running box and re-logging
  did **not** clear the X: the greeter Xorg had already programmed the plane at
  the pre-fix boot and SPICE's overlay cannot be retracted. The override only
  works **applied from boot** — which the installer guarantees, and which a full
  reboot confirmed empirically.
- **Host-side (change the VM's video model / SPICE cursor mode).** Would fix only
  the harness, not the guest install, and touches the VM definition rather than
  the thing we ship. Rejected as out of the installer's scope.
- **Accept it.** Legitimate — it is VM-only and cosmetic. Pursued the fix because
  the *inconsistency* (compositor-only VMs clean, KDE VMs not) was the real wart;
  one gated drop-in removes it.

## Consequences

- KDE-bearing VMs get a clean cursor on the SDDM login screen and in every
  session; the artifact's last surface is closed.
- Real hardware is byte-for-byte unaffected — the drop-in is never written off a
  VM, and hardware cursors stay optimal.
- The workaround is only correct from boot; there is no live-apply path (an
  installer-produced file always satisfies this).
