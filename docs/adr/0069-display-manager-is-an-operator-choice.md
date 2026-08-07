# Display manager is an operator choice, not derived from the desktop set

---
Status: accepted (supersedes ADR 0067's "greetd owns the DM whenever
Hyprland is installed")
---

The display manager is now selected by the operator via
`environment.display_manager` (`auto` | `greetd` | `sddm`, default `auto`),
not auto-derived from the resolved desktop set. Full symmetry: any DM launches
any DE — SDDM for Hyprland or KDE+Hyprland, greetd for KDE.

ADR 0067 forced greetd whenever Hyprland was installed because an
SDDM-launched Hyprland session could not obtain DRM master. ADR 0068 then
root-caused that to logind and fixed it with **seatd**, which the Hyprland
adapter installs and enables **unconditionally**, independent of the DM. With
DRM-master decoupled from the DM, greetd is no longer *required* for Hyprland —
so the DM becomes a choice.

`auto` resolves at config-load: `greetd` if `hyprland` is in the desktop set,
else `sddm`, and `none` when no desktop is selected. Every profile that omits
the key therefore behaves exactly as it did under ADR 0067. A **concrete** DM
with an empty desktop set aborts at config-load (a greeter with no session).

The DM logic is extracted into a **Display Manager Adapter**
(`extras/dm/<name>/<name>.sh`), dispatched by the Environment Runner **after**
the desktop loop, mirroring the DE and bootloader adapter conventions (ADR
0003/0005). The DM adapter owns its **package install + config + enable**; the
DE adapters own **session files + seatd** and no longer touch any DM.

## Considered options

- **Keep greetd forced for Hyprland (ADR 0067)** — rejected: seatd removed the
  reason it was forced, and the operator wants SDDM where Hyprland is present.
- **Branch on the DM inside each DE adapter** — rejected: smears DM logic
  across two adapters and worsens the co-install "who enables what" coordination;
  extraction matches the convention-dispatch pattern the repo already uses twice.

## Consequences

- SDDM is **no longer installed by the KDE adapter** — each DM adapter installs
  its own DM, so SDDM on a Hyprland-only host finally has an owner. `sddm-kcm`
  stays a KDE application, not a DM concern.
- greetd's `config.toml` (tuigreet pointed at the curated
  `/usr/local/share/wayland-sessions`) moves from the Hyprland adapter into
  `dm-greetd`; the Hyprland adapter keeps writing the curated session files.
- `dm-sddm` writes a `Wayland.SessionDir` (+ X `SessionDir`) sddm.conf.d drop-in
  pinning the curated `/usr/local/share/wayland-sessions` **ahead of**
  `/usr/share`, so SDDM and greetd present the same curated, deduped session
  list and the packaged crashy `hyprland.desktop` is shadowed deterministically.
- **SDDM-launched Hyprland is proven in the VM (software GPU)** — the
  `desktop-verify` harness autologs into `hyprland.desktop` via SDDM and the
  session comes up (`===HYPR-SESSION-OK===`). It is **unproven on real amd
  hardware**, the logind-master failure site ADR 0068 fixed with seatd; that is
  verified on the next real install, and a failure re-opens this ADR (the
  operator declined a HITL gate, as in ADR 0061).
- The **VM verify harness** always installs sddm to drive its autologin prober
  (a launcher, not the product) and additionally asserts the resolved DM's
  service is `is-enabled`, so a greetd profile still checks the right DM.
- The [[Package Resolver]] reports `sddm` / `greetd` / `greetd-tuigreet` as a
  `display-manager`-keyed derived set driven by the resolved `display_manager`,
  rather than smuggling `sddm` inside the `kde-shell` set (`sddm-kcm` stays a KDE
  app).
- The Guided Installer gains an `environment.display_manager` row
  (Auto / greetd / SDDM).
- Impermanence is unchanged: the enablement relocation follows the DM-agnostic
  `display-manager.service` alias (ADR 0061).
