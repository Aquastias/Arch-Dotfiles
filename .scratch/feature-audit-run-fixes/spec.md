# Spec: Fix the first full Audit Run's Findings

Status: ready-for-agent

Source: Audit Run `20260929-200142` (`findings.md`, 1086 [[Finding]]s).
Anchored by **ADR 0152** (Feature Audit), amending **ADR 0078** (ESP
auto-size), **ADR 0052** (AUR-helper ladder) and **ADR 0152** itself. Uses
[[Feature Audit]], [[Audit Run]], [[Audit Variant]], [[Audit Manifest]],
[[Finding]], [[Known Noise]], [[Probe Gate]] (new), [[Host Profile]],
[[Pure (Stock) Profiles]], [[Minimal Profile]], AUR Helper, Console
Answerer. Respects ADR 0080 (tuned pulls tuned-ppd), ADR 0135 (nvim on
lazy.nvim, system LSPs), ADR 0112 (pure profiles are stock).

## Problem Statement

The first full Audit Run reported 1086 Findings. The list is unworkable:
~60% are reporter artefacts (one journal entry split into many Findings,
per-mount/per-PID duplicates, pacman "up to date" chatter, AUR compiler
output). Six variants never got audited past install or boot (grub,
minimal, tuned, guided, efistub/limine/refind, ufw), so their features are
unproven. Probes assert the opinionated config on variants that by design
do not ship it (pure, no-shell, services-off), drowning real failures.
Under the noise sit genuine product bugs: corrupt systemd-boot fallback
entries, a grub install that can never pass validation, rkhunter's unit
pointing at a missing script, vconsole failing, ufw locking out ssh,
nvim unusable offline, nixd crashing, and more.

## Solution

Work the Findings by root-cause cluster, one `.scratch` issue per cluster
listing its Finding ids, in this order: fatals/harness → reporter →
probes/scenes → product bugs → one batched Known Noise list for maintainer
approval → a final full Audit Run with zero Findings → visual review of
the screenshot gallery. Each cluster is re-checked with `run --reuse` /
`--variant` before moving on.

## User Stories

1. As the maintainer, I want Findings grouped by root cause, so that one
   fix closes every Finding it caused.
2. As the maintainer, I want each cluster issue to list its Finding ids,
   so that I can trace every Finding to a resolution.
3. As the maintainer, I want every Audit Variant to install and boot, so
   that no feature goes unaudited behind a fatal.
4. As the maintainer, I want a grub install with `esp_size: auto` to pass
   validation, so that grub is actually installable.
5. As the maintainer, I want the 1G ESP floor to stay absolute for every
   loader, so that there is one rule, not a per-loader exception.
6. As an operator on a 4G machine, I want the AUR helper to bootstrap
   without the source build being OOM-killed, so that small hosts install.
7. As an operator, I want a bootstrapped AUR helper to be accepted only if
   it actually runs, so that a stale `-bin` linked to an old libalpm does
   not abort the install later.
8. As an operator choosing `tuned`, I want the install to not abort on the
   tuned-ppd / power-profiles-daemon conflict, so that tuned is usable on
   Plasma.
9. As the maintainer, I want efistub, limine and refind boots to print on
   serial, so that the Console Answerer can unlock the encrypted root.
10. As the maintainer, I want the guided variant to reach the harness repo,
    so that the guided path is audited.
11. As an operator with ssh enabled and ufw as firewall, I want ssh
    allowed, so that I am not locked out of my machine.
12. As an operator, I want systemd-boot fallback entries free of
    mkinitcpio output, so that the fallback actually boots.
13. As the maintainer, I want one journal entry to be one Finding, with
    its continuation lines folded in, so that stack traces and wrapped
    messages don't multiply.
14. As the maintainer, I want hex ids, PIDs and similar volatile tokens
    normalised before dedup, so that 38 "unmount busy" lines are one
    Finding.
15. As the maintainer, I want pacman "up to date -- skipping" and AUR
    build output not treated as errors, so that the install log is
    readable.
16. As the maintainer, I want Finding ids wide enough for any run, so that
    the 1000th Finding is not `F000`.
17. As the maintainer, I want Known Noise entries optionally scoped to
    variants, so that stock behaviour on pure profiles is noise there but
    still a Finding on the base.
18. As the maintainer, I want a probe check to declare its Probe Gate, so
    that it reports SKIP (not FAIL) on variants that lack its conditions.
19. As the maintainer, I want skipped checks visible in the report, so
    that a gate never silently hides a gap.
20. As the maintainer, I want our bind expectations skipped where our
    compositor config is not deployed (pure profiles), so that stock
    binds aren't judged against ours.
21. As the maintainer, I want Noctalia binds skipped when
    `wayland_shell: none`, so that no-shell variants judge only what they
    ship.
22. As the maintainer, I want apparmor/bluetooth probes skipped on
    services-off, so that disabled-by-design is not a failure.
23. As the maintainer, I want xdg-user-dirs checks gated on the package,
    so that stock Hyprland is not judged by our userland.
24. As the maintainer, I want nvim bind scenes to set up the state each
    bind needs (folds, an http buffer, a git remote, a diff, tags), so
    that bind failures mean a broken bind.
25. As the maintainer, I want the KDE bind scenes for Meta+K, Meta+D and
    Meta+7 to set up their preconditions, so that they test the bind.
26. As the maintainer, I want apps launched by VM Agent Control to get the
    user session environment, so that Qt does not fall back to locale C.
27. As a user, I want nvim plugins installed at install time from the
    lockfile, so that nvim (LSP, DAP, binds, theme) works offline on first
    launch.
28. As a user, I want nixd backed by nix, so that the Nix LSP does not
    abort.
29. As a user, I want the rkhunter timer to run its script, so that daily
    scans happen.
30. As a user, I want the console font applied at boot, so that
    systemd-vconsole-setup does not fail.
31. As a user, I want Noctalia plugin fetches retried on a transient
    network error, so that a blip does not drop plugins.
32. As a KDE user, I want my colour scheme kept after login, so that
    Plasma does not reassert BreezeDark.
33. As a user, I want searxng's user unit running and answering on
    127.0.0.1:8080, so that local search works.
34. As a user, I want borgmatic's timer to succeed, so that backups run.
35. As a user, I want teamspeak3 to launch, so that I can use it; if it
    cannot be fixed downstream, I want it marked `unverifiable` with a
    reason instead of silently tolerated.
36. As a user, I want S3 suspend to work on greetd, services-off and ufw
    variants, so that power management is consistent.
37. As the maintainer, I want the firewalld iptables errors, tmpfiles-clean
    and libvirtd failures diagnosed, so that each is fixed or explained.
38. As the maintainer, I want every proposed Known Noise entry (regex +
    reason) presented in one batch, so that I approve them in one pass.
39. As the maintainer, I want upstream/VM-inherent lines (aquamarine/EGL
    fallback, xkb keysym warnings, RTKit, portal registration, QEMU SMART,
    shutdown unmount busy, stock Hyprland config generation) handled as
    Known Noise with reasons, so that they stop being Findings.
40. As the maintainer, I want a final full Audit Run with zero Findings,
    so that "every shipped feature works" is proven, not assumed.
41. As the maintainer, I want the screenshot gallery reviewed after the
    product fixes, so that theming breakage becomes Findings too.

## Implementation Decisions

**Process**
- One issue per root-cause cluster under this directory, each listing its
  Finding ids from `20260929-200142`. Order: B (fatal/harness) → A
  (reporter) → D (probes/scenes) → C (product) → E (Known Noise batch) →
  full run → visual review.

**B. Fatals / harness**
- ESP: grub's `auto` resolves to 1G; the 1G floor stays absolute for all
  loaders. Amend ADR 0078 (it said both "grub takes a fixed small ESP"
  and "1G is the absolute floor").
- AUR helper ladder (amend ADR 0052): a rung only counts if the helper
  runs (`--version`); otherwise fall to the next rung. Rung 1's source
  build runs with LTO off and limited cargo jobs for the bootstrap only,
  so it fits in 4G. The ladder's shape (source → paru-bin → yay-bin) is
  unchanged.
- tuned: when the power profile is tuned, tuned + tuned-ppd are installed
  before the DE packages so tuned-ppd satisfies the power-profiles-daemon
  dependency. Arch Wiki-grounded.
- Seed generator: inject `console=ttyS0` for every bootloader, not only
  systemd-boot and grub.
- Guided variant: the guided test flow serves/reaches the audit's
  dumb-HTTP repo like the persistent flow does.
- ufw: when ssh is enabled, the ufw setup allows ssh.
- systemd-boot: fallback image staging must not leak its build output into
  the entry; only the image name is captured.

**A. Reporter (`feature-audit.sh report`)**
- Journal continuation lines (indented, stack-trace frames, wrapped
  messages) fold into their head entry.
- Volatile tokens (hex ids, PIDs, mount hashes, unit instance suffixes)
  are normalised in the dedup key; the excerpt keeps one real sample.
- pacman "is up to date -- skipping" is not error-shaped. AUR build output
  from the helper's clone directories goes to Known Noise with a reason
  (real error-shaped upstream output; Known Noise stays the only semantic
  filter).
- Finding ids are zero-padded to the run's total width.
- Known Noise schema gains optional `variants: [..]`; absent = global.
- Skipped probe checks are counted and listed in the report.

**D. Probes / scenes**
- Probe Gate in the probe lib: a check (or whole probe) declares the
  Host Profile conditions it needs, e.g. our config deployed (not stock),
  a wayland shell present, a service enabled, a package installed. The
  guest gets the variant's profile; an unmet gate prints SKIP with the
  reason. Add [[Probe Gate]] to ADR 0152 as an amendment, along with
  variant-scoped Known Noise.
- Bind probes: skipped when our compositor config is not deployed;
  Noctalia binds skipped when there is no wayland shell.
- nvim bind fixtures provide folds, an http request buffer, a git remote,
  a diff and a tag stack where binds need them.
- KDE scenes: Meta+K starts krusader first; Meta+D and Meta+7 set up
  windows / task-manager entries first.
- VM Agent Control launches apps with the user session environment
  imported from the user manager.

**C. Product**
- nvim: at install, a headless lazy restore from the lockfile, as the
  user, staged for `/etc/skel` and `/root` like the theme. No ADR.
- `nix` installed alongside `nixd` in Host Core's language servers (Arch
  Wiki-grounded).
- rkhunter unit runs the script where the installer actually puts it.
- vconsole.conf is written before the initramfs is built.
- Noctalia plugin fetch: shallow retry with backoff before skipping.
- Diagnose on a held VM, then fix: BreezeDark reassert, searxng unit,
  borgmatic, teamspeak3 launch (try Qt platform/env first), S3 on
  greetd/services-off/ufw, firewalld iptables, tmpfiles-clean, libvirtd.

**E. Known Noise / unverifiable**
- One batched list of `{regex, source?, phase?, variants?, reason}` for
  maintainer approval before commit.
- Anything unfixable upstream: `unverifiable` in the Audit Manifest with a
  reason, plus a Known Noise entry for its log lines.

## Testing Decisions

- Good tests assert external behaviour at the highest seam: given inputs
  (a run folder, a manifest, a profile), the tool's output. Never internal
  helpers.
- `feature-audit.sh report` (`report.bats`, synthetic run folders):
  continuation folding, token normalisation, pacman up-to-date ignored,
  id width ≥ 1000 findings, variant-scoped noise, skipped checks reported.
- `feature-audit.sh check` (`check.bats`): every manifest variant
  validates (catches grub ESP); noise schema accepts `variants`.
- Probe lib gates (new bats, the only new seam): fixture Host Profiles
  (stock, `wayland_shell: none`, services off) → SKIP with reason; base
  profile → check runs.
- Existing installer units: `esp-budget.bats` (grub auto = 1G, floor
  holds), `loader-entries.bats` (fallback entry clean when staging is
  noisy), `seed-generator.bats` (console=ttyS0 for every loader),
  `profiles-bootstrap.bats` (rung rejected when the helper doesn't run;
  bootstrap build env).
- Acceptance: the Feature Audit itself. Per-cluster `run --reuse` /
  `--variant` re-checks; a final full Audit Run must report zero Findings.
- Prior art: `report.bats` / `check.bats` / `binds.bats` style (pure,
  tmpdir fixtures, tool invoked as a subprocess).

## Out of Scope

- New features or new variants beyond what the Findings require.
- Storage-axis coverage (owned by the Combination Matrix, ADR 0046).
- Fixing upstream bugs in closed-source or third-party code; those become
  `unverifiable` / Known Noise.
- Secure Boot, TPM, real GPUs, bluetooth hardware (already unverifiable).

## Further Notes

- Facts behind the decisions, from the run logs: grub fails at
  validation (`esp_size 512M below the 1G floor`); minimal's paru source
  build was SIGKILLed, paru-bin then installed but fails to load
  `libalpm.so.15`; tuned aborts on the tuned-ppd conflict prompt;
  efistub/limine/refind serial goes silent after the loader; guided can't
  connect to the harness repo; ufw variant refuses ssh; rkhunter's unit
  execs a path the installer never writes; mkinitcpio warns
  vconsole.conf missing during install.
- Known Noise needs maintainer approval per ADR 0152; nothing is added
  without it.
