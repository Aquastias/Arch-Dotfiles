# VM profiles seed a Full-HD virtual panel, out-of-guest

---
Status: accepted. **Qualifies ADR 0110** (compositor/KDE resolution is never
seeded in-guest) for the VM case: the in-guest invariant is unchanged — no mode
in niri/Hyprland configs, `kscreenrc`/`kwinoutputconfig.json` still excluded from
the KDE capture (ADR 0111) — the panel is fixed at the **virtual-hardware** layer
instead.
---

ADR 0110 refuses to seed a resolution because a monitor mode is machine-physical
(EDID-keyed) and a hardcoded mode black-screens mismatched hardware. That holds
for real machines. But a VM's virtual display advertises whatever the *hypervisor*
configures, and the default SPICE/QXL surface can come up small — so a fresh VM
install lands below Full HD until someone resizes it by hand. The operator asked
that "just for VMs, at least Full HD resolution" be guaranteed.

## Decision

**For VM Host Profiles only, define the virtual display at ≥ 1920×1080 in the VM
definition (libvirt/qemu video device), not inside the guest.** Autodetection
then does exactly what ADR 0110 wants — the guest's compositor/kscreen picks the
*preferred* mode — except the preferred mode is now Full HD because that is what
the virtual panel advertises. Nothing is seeded in-guest: the niri/Hyprland
configs stay output-less, the KDE capture keeps excluding the EDID-keyed
`kscreenrc`/`kwinoutputconfig.json`. Real hardware is untouched (no VM
definition), so ADR 0110's black-screen risk never applies.

## Considered options

- **Seed `kscreenrc`/`kwinoutputconfig.json`** with a Full-HD mode — rejected:
  those files are EDID-hash-keyed (ADR 0111 excludes them for exactly this
  reason); a seeded output block is non-portable and fights autodetection.
- **First-login `kscreen-doctor`/`wlr-randr` autostart** clamping to ≥ FHD —
  rejected: in-guest, per-session, races the compositor bring-up, and re-encodes
  a mode the hypervisor already knows; the virtual-hardware layer is the honest
  owner of "what panel does this VM have".
- **Hardcode a mode in the guest configs** — rejected for the ADR 0110 reasons;
  this ADR deliberately keeps that invariant.

## Consequences

- VM installs come up at Full HD unattended; real installs are unchanged and
  still autodetect their native mode.
- "At least" is the contract — the virtual panel is a floor, not a pin; a larger
  host window / higher SPICE surface still scales up via preferred-mode
  autodetection.
