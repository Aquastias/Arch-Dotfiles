# 09 — Docs & comments sync

**What to build:** The repo's domain docs and comments match the shipped code for
ADRs 0110–0113 — a reader of CONTEXT.md, the README/REFERENCE, and the adapter
comments finds the captured-settings seed, the stock environment variants, the
Meta+X close, and the resolution-autodetect decision described accurately and in
the glossary's vocabulary. (ADRs 0110–0113.)

**Blocked by:** 01, 02, 04, 05, 06, 07, 08 (docs describe the shipped behaviour).

**Status:** ready-for-agent

- [ ] CONTEXT.md glossary updated: the [[Desktop Environment Adapter]] and
      [[Environment Config]] entries describe `environment.stock` and the
      captured KDE seed; a note on Meta+X close; resolution stays autodetected.
- [ ] README.md / REFERENCE.md updated for the `*-pure` profiles and the guided
      `stock` toggle.
- [ ] Adapter and keybind comments use the compact style (the non-obvious *why*
      plus its `(ADR NNNN)` anchor), referencing ADRs 0110–0113.
- [ ] A regression guard asserts the seeded niri/Hyprland configs contain no
      hardcoded resolution/output mode (ADR 0110).
- [ ] Full test suite green.
