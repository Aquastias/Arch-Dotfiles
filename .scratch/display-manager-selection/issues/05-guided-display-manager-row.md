# 05 — Guided Installer Display Manager row

**What to build:** The operator using the Guided Installer picks the greeter
from the menu. The Environment category gains a `display manager` row offering
Auto / greetd / SDDM, with the standard override dot when changed, and the
category summary names the display manager. The choice is stored in Config State
and flows through Proceed, Export, and Save like any other Environment field, so
selecting SDDM in the menu installs SDDM.

**Blocked by:** 01.

**Status:** ready-for-agent

- [ ] The Environment category shows a `display manager` row with enum options
      `auto`, `greetd`, `sddm` (default `auto`) and Display Labels Auto /
      greetd / SDDM.
- [ ] The row carries the standard override dot only when the operator changes
      it; the Environment category summary names the display manager.
- [ ] The selection is written to Config State under
      `environment.display_manager` and is carried by Proceed, Export, and Save
      Profile (a delta over Host Core).
- [ ] The enum and Display Label come from the single shared source so the
      interactive and replay front-ends cannot drift.
- [ ] The guided-menu and menu-enum bats cover the row, its options, and its
      labels (prior art: the desktop/gpu row and enum cases).
