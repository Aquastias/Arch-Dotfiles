# ADR 0152: Feature Audit: max-feature variants, probes, offline-first

## Status
Accepted — design only; not yet implemented. Amended 2026-10-02 (Probe
Gate; variant-scoped Known Noise).

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
- **Keys are QMP `input-send-event`**, not `virsh send-key`: a chord's
  modifiers must stay held around the key (and around pointer input for
  Super+drag / Super+wheel binds), which send-key cannot express.
- **Power is its own phase** (S3 wake + S4 resume need the host to wake or
  restart the VM), and **desktop probes run inside each session phase**.
- **Iteration aids:** `run --reuse` audits a kept VM without reinstalling
  and `FEATURE_AUDIT_SKIP` drops phases; both are for re-checking fixes, a
  full Audit Run never uses them.
- **Base power daemon is power-profiles-daemon**; `tuned` is a variant, as it
  conflicts with the ppd Plasma pulls (a real install abort the first run
  found).
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

## Amendment (2026-10-02): Probe Gate and variant-scoped Known Noise

The first full Audit Run judged variants by features they do not ship:
apparmor/bluetooth on `services-off`, our binds and userland on the Pure
Profiles, Noctalia on `no-shell`. Those FAILs drowned the real ones.

- **Probe Gate**: a check declares the Host Profile conditions it needs;
  on a variant lacking them it is reported SKIP with the reason — never
  PASS, never a Finding. Program level: the runner resolves the variant's
  selected programs (host, user, Security & Backup Extras) and skips the
  probes of the rest. Check level: probe-lib gates (`fa_gate`,
  `fa_stock`, `fa_curated`, `fa_has_shell`). Every skip is listed in
  `findings.md`, so a gate never hides a gap silently.
- **Known Noise `variants`**: an entry may name the Audit Variants it holds
  for (stock behaviour on a Pure Profile is noise there and still a Finding
  on the base). `check` rejects unknown variant ids.

Rejected: asserting stock compositors' own binds on Pure Profiles — they
prove upstream defaults, not anything this repo ships (ADR 0112).

## Amendment (2026-10-04): a full run in one night

A full run took ~25h: 18 variants in series, each a from-scratch install
(31 AUR builds) and every phase, plus ~25 min of fixed sleeps per variant.
Three changes, still one VM at a time:

- **Variant Phases**: a variant declares the phases its change can affect
  (manifest `phases`; absent = all; install + boot1 always run). Base and
  the real/pure hosts run all; e.g. bootloader variants run boot2 + upgrade.
  A skipped phase is a SKIP in `findings.md`, and `check` (family `phases`)
  fails if any phase, installed desktop's binds or selected program's probe
  no longer runs in some variant.
- **Audit Cache**: base installs uncached (real mirrors, AUR builds, AUR
  Vetting), keeping its packages; the harness harvests them after boot1 —
  repo packages as a pacman `CacheServer`, built AUR packages as an
  `[audit-aur]` repo — and points every later install of the run at them
  (test-only installer env; the installed `pacman.conf` is stripped back to
  shipped). Wiped when a run installs base again. If base never boots,
  the rest install uncached.
- **Readiness waits**: boot settle, session settle and the timer soak wait
  for the guest to be quiet (no jobs, nothing activating, shell up), with
  the old fixed values as caps.

Rejected: parallel VMs for now (they share the virgl GPU that already
stalls; revisit if a run misses ~10h); batching nvim binds into one nvim
(per-bind isolation keeps failures attributable); a persistent cross-run
cache (staleness for no gain, base installs uncached anyway).
