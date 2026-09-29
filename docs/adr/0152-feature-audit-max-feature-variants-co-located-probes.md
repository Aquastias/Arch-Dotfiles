# ADR 0152: Feature Audit: max-feature variants, probes, offline-first

## Status
Accepted — design only; not yet implemented.

## Context
The Combination Matrix (ADR 0046) proves storage combinations install and
boot, but nothing proves every shipped feature (151 ADRs, ~55 programs,
three compositors) works end to end. Hidden errors surface only on real use:
first login, a plugin, a keybind, a timer, an upgrade.

## Decision
- **Feature Audit** (`tools/feature-audit.sh`): installs a max-feature base
  (`hosts/vm/arch-audit`) plus Audit Variants, each a JSON patch over it
  that swaps one mutually-exclusive feature (bootloaders, firewall, power
  daemon, pure/minimal profiles, a guided install) or installs a real host
  (`desktop`, `laptop`, `core`) as-is. Storage axes stay with the matrix. One
  VM at a time, via the persistent flow + VM Agent Control (ADR 0117).
- **Error = Finding** unless matched by committed Known Noise (regex +
  reason, user-approved). Collected from install log, every boot (failed
  units, journal ≥ warning, coredumps), every session, forced timers + soak,
  and a final `pacman -Syu` + reboot phase. Never stops on a Finding; only a
  fatal install/boot aborts a variant.
- **Probes co-located** with each program (`audit.sh`, `audit-binds.jsonc`),
  part of the program contract. A program without a probe, a feature no
  variant enables, or a shipped keybind without a declared expectation is
  itself a Finding. Binds are tested by real keyboard/mouse input.
- **Offline-first**: probes run once with guest network cut; a feature that
  only works online after install is a Finding ("runtime fetch").
- **Emulate the maximum libvirt allows** for what the installer ships:
  SATA disks for SMART, a real IPP Everywhere job (the guest's own
  `ippeveprinter`), ACPI S3 suspend/wake and S4 resume (VM created with
  `--pm`). Secure Boot and TPM were planned but dropped: the installer ships
  neither (no signing, no `cryptenroll`), so emulating them proves nothing.
  The rest (bluetooth, lact/real GPUs, fwupd updates, laptop battery/lid,
  teamspeak connect) is `unverifiable` in the Audit Manifest,
  user-reviewed before the first run; still probed as far as the VM allows
  (service/app starts clean).
- **The guest audits committed HEAD**: the run serves the local repo as a
  dumb-HTTP bare clone on the harness HTTP root, so no push is needed and
  uncommitted changes are not audited.
- **nvim keymaps** go through nvim's own input queue (headless, one fresh
  nvim per bind, the user's real config); the terminal layer is proven by
  kitty's binds, sent as real keyboard input like the compositors'.
- Output: `findings.md` (agent-ready) + `findings.jsonl` + raw logs and a
  screenshot gallery for visual review, under a gitignored run directory.
  Manual only; bats covers just the manifest coverage check.

## Considered Options
- Extending the matrix with a deep tier: its cells are headless and
  combinatorial; the audit needs desktops and breadth, not combinations.
- A central probe library: new programs would ship silently untested.
- Hand-picked keybind subset: untested binds would accumulate.
