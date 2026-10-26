# 07: Feature Audit probe

**What to build:** An Audit Run proves the [[Emacs Config]] on a real host
(ADR 0152 contract, prior art: the nvim and vscodium probes). The probe
requires the package, runs as the user, and checks: Emacs runs; the seeded
Doom config exists; the Doom clone is at the pinned commit; `doom doctor`
reports no errors; each planned bind in an audit binds file resolves to its
command via `emacs --batch` with Doom loaded.

**Blocked by:** 03 (Keymaps), 04 (Theme), 05 (Org and REST), 06 (Debuggers).

**Status:** ready-for-agent

- [ ] Probe follows the program-spec audit contract; skips cleanly when emacs
      is not installed
- [ ] Pin check reads the same pin data file install.sh uses
- [ ] Binds file covers representative binds from tickets 03–06
- [ ] Known-noise entries (if any) documented like other probes'
- [ ] Audit Run on the VM: all emacs checks pass; output in Comments

## Comments
