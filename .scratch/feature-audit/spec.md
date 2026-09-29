# Spec: Feature Audit

Status: ready-for-agent

Anchored by **ADR 0152**. Uses the [[Feature Audit]], [[Audit Variant]],
[[Audit Manifest]], [[Known Noise]], [[Finding]], [[Audit Run]] glossary terms
(new), plus [[VM Harness]], [[VM Profile]], [[Agent-Controllable VM]], [[VM
Agent Control]], [[Combination Matrix]], [[Host Profile]], Effective Config.
Respects ADR 0046 (matrix owns storage axes), ADR 0099 (hold-on-fail), ADR
0117 (agent control + toolkit-test convention), ADR 0141 (language
registry), ADR 0146 (root shell), ADR 0139 (archzfs ceiling hold).

## Problem Statement

The installer ships ~151 ADRs of features: three compositors, Noctalia
theming, ~55 programs, nvim with plugins/LSPs/formatters/DAP, SOPS,
impermanence, encryption, security/backup/power stacks, several
bootloaders. The Combination Matrix only proves storage combinations install
and boot, headless. Nobody proves the installed system is *fully
functional*: errors hide in first-login journals, failed user units, plugins
that silently fail, keybinds that do nothing, timers that fail hours later,
first-launch downloads, and the first `pacman -Syu`. Each is found by
accident, one at a time, on real hardware.

## Solution

A committed, manual, re-runnable tool that installs a max-feature VM plus
Audit Variants (one mutually-exclusive feature swapped each, or a real host
as-is), one VM at a time. It collects every error-shaped signal from install
through the final upgrade reboot, exercises every program through a probe
co-located with it (plugins functionally, every shipped keybind through real
keyboard/mouse input), and writes one agent-ready findings list. Workflow:
build the tool, run once, document all Findings, fix them all in one
session, rerun until clean. Re-run later whenever features are added or
fixed; new programs/binds/features that lack coverage fail the audit.

## User Stories

1. As the maintainer, I want one command that audits every shipped feature
   in VMs, so that hidden errors surface before they reach hardware.
2. As the maintainer, I want the audit committed in the repo, so that I can
   rerun it after adding features or fixing bugs.
3. As the maintainer, I want a max-feature base install, so that most
   features are exercised by a single VM.
4. As the maintainer, I want the base to be a real Host Profile, so that the
   audit goes through the real Profile Loader rather than a test-only path.
5. As the maintainer, I want Audit Variants expressed as small patches over
   the base, so that each variant's difference is obvious at a glance.
6. As the maintainer, I want variants for each alternate bootloader (grub,
   limine, refind, efistub), so that every bootloader path is proven.
7. As the maintainer, I want ufw and power-profiles-daemon variants, so that
   the non-default side of each exclusive pair is proven.
8. As the maintainer, I want the pure profiles and minimal profile as
   variants, so that stock setups are proven too.
9. As the maintainer, I want one guided (menu-driven) install variant, so
   that the interactive path is audited, not only unattended.
10. As the maintainer, I want my real hosts (desktop, laptop, core)
    installed as-is as variants, so that what I actually install is proven.
11. As the maintainer, I want storage combinations left to the Combination
    Matrix, so that the two tools don't duplicate each other.
12. As the maintainer, I want variants to run one VM at a time with a
    host-capacity guard, so that the host stays usable.
13. As the maintainer, I want to run a single variant, or resume from one,
    so that a rerun after fixes doesn't redo everything.
14. As the maintainer, I want the VM destroyed between variants, so that
    each install starts clean.
15. As the maintainer, I want `--keep` to hold the last VM, so that I can
    inspect it after the run.
16. As the maintainer, I want the run to never stop on a Finding, so that
    one run documents everything.
17. As the maintainer, I want a fatal install/boot failure to abort only its
    variant and be recorded as a Finding, so that the rest of the run still
    happens.
18. As the maintainer, I want installer log errors, warnings, non-zero steps
    and pacman/AUR/hook warnings captured, so that install-time problems are
    visible.
19. As the maintainer, I want every boot's failed system and user units,
    journal lines at warning and above, coredumps and kernel errors
    captured, so that boot-time problems are visible.
20. As the maintainer, I want at least two boots per variant, so that
    impermanence rollback, persistence and SOPS decryption on reboot are
    proven.
21. As the maintainer, I want each desktop session (KDE, niri, Hyprland)
    logged into and its user journal and compositor log collected, so that
    session-start errors are visible.
22. As the maintainer, I want a screenshot per session and per launched app,
    so that visual problems can be reviewed.
23. As the maintainer, I want a probe for every program, living next to the
    program, so that new programs ship with their audit.
24. As the maintainer, I want a program without a probe (and not marked
    unverifiable) to be a Finding, so that coverage cannot silently rot.
25. As the maintainer, I want a feature no variant enables to be a Finding,
    so that new options are not forgotten.
26. As the maintainer, I want plugins tested functionally (every nvim plugin
    spec loads, clean checkhealth, each LSP/formatter/DAP adapter works on a
    sample file per registry language; zsh plugins load with no stderr;
    Noctalia/KDE plugins load), so that "installed" means "working".
27. As the maintainer, I want every shipped keybind parsed from the real
    configs (niri, hyprland, KDE, nvim, kitty, zsh), so that the bind list
    is never hand-kept.
28. As the maintainer, I want each bind sent as real keyboard or mouse input
    and its declared effect asserted (window/app appears, focus/workspace
    changes, process starts), so that binds are proven, not assumed.
29. As the maintainer, I want a shipped bind without a declared expectation
    to be a Finding ("untested bind"), so that bind coverage cannot rot.
30. As the maintainer, I want session-ending binds (quit, logout, lock,
    poweroff) run last with a recovery step, so that they don't break the
    rest of the probes.
31. As the maintainer, I want probes run once with the guest network cut,
    so that any first-launch download is a Finding ("runtime fetch").
32. As the maintainer, I want probes that genuinely need network (docker
    pull, reflector, freshclam) rerun with network restored, so that they
    are still verified.
33. As the maintainer, I want probes run for every user in the variant plus
    root, so that per-user and root shell setups are proven.
34. As the maintainer, I want every enabled timer's unit force-started and a
    10-minute idle soak before harvest, so that delayed failures surface.
35. As the maintainer, I want a final `pacman -Syu` and reboot per variant,
    so that upgrade hooks, dkms/archzfs holds, mkinitcpio and bootloader
    updates are proven; its Findings tagged `phase=upgrade`.
36. As the maintainer, I want Secure Boot, TPM, SMART (SATA disk), printing
    (virtual IPP printer) and suspend/hibernate emulated, so that the VM
    covers the maximum libvirt allows.
37. As the maintainer, I want non-emulatable features (bluetooth, real GPU /
    lact, fwupd updates, laptop battery/lid, teamspeak connect) marked
    `unverifiable` with a reason in the Audit Manifest, and still probed as
    far as possible (service/app starts clean), so that the gap is explicit.
38. As the maintainer, I want to review the unverifiable list before the
    first run, so that nothing is waved through.
39. As the maintainer, I want a committed Known Noise allowlist (regex +
    reason/ADR), starting empty, so that only approved lines stop being
    Findings.
40. As the maintainer, I want every Known Noise entry approved by me, so
    that real errors aren't hidden by convenience.
41. As the maintainer, I want an agent-ready `findings.md` (id, variant,
    phase, source, program/ADR, deduped excerpt, raw log path, repro
    command), so that I can hand it straight to an agent to fix.
42. As the maintainer, I want a machine-readable `findings.jsonl`, so that
    tooling can diff runs.
43. As the maintainer, I want identical Findings across variants merged
    into one entry listing the variants, so that the list is not
    repetitive.
44. As the maintainer, I want intermittent Findings shown with their
    frequency (e.g. 2/3 boots), so that flaky issues are visible, not
    retried away.
45. As the maintainer, I want a visual-review section listing screenshots,
    so that the fixing agent can judge theming the scripts can't.
46. As the maintainer, I want raw logs kept in a gitignored run directory,
    so that every Finding is traceable without polluting the repo.
47. As the maintainer, I want a non-zero exit on any Finding, so that
    "clean" is unambiguous.
48. As the maintainer, I want the manifest/coverage check runnable without
    a VM and covered by bats, so that coverage drift is caught cheaply.
49. As the maintainer, I want the report step runnable on an existing run
    directory without a VM, so that the judging logic is testable and I can
    re-judge after editing Known Noise.
50. As the maintainer, I want the audit manual-only (no pre-push/CI), so
    that multi-hour libvirt runs never block normal work.
51. As an agent fixing Findings, I want each Finding to carry a repro
    command and log path, so that I can reproduce it on a kept VM.
52. As an agent writing a new program, I want the probe contract documented
    in the program spec, so that I know what audit files to ship.

## Implementation Decisions

- **Entry point**: a new tool alongside the matrix tool with subcommands:
  - `check` — pure: resolve manifest (base + each patch → Effective Config,
    validated like the VM Harness validates profiles), coverage (programs ↔
    probes/unverifiable, features ↔ variants, parsed binds ↔ declared
    expectations). Coverage gaps are Findings.
  - `run [--variant X] [--from X] [--keep]` — live; runs `check` first,
    then variants sequentially; each variant ends with a `report` pass.
  - `report <run-dir>` — pure: raw artifacts → Findings.
- **Host lib** in its own `lib/feature-audit/` area (manifest, coverage,
  bind parsers, collectors, report), sourced by the entry point; mirrors the
  matrix tool's split so helpers are unit-testable.
- **Base host**: a new committed VM Host Profile `arch-audit`: kde + niri +
  hyprland with Noctalia, SOPS (Test Age Key), impermanence, ZFS native
  encryption, 2-disk mirror + data pool, swap, every security/backup/power
  option, every program in the registry, Secure Boot hardening. Hardware
  adds swtpm, OVMF secboot vars, and one SATA disk for SMART.
- **Audit Manifest**: committed JSONC under the tests VM tree. Lists
  variants (id, patch over base or real-host reference, ADRs covered) and
  `unverifiable` entries (feature/program, reason). Initial variants: grub,
  limine, refind, efistub, ufw, power-profiles-daemon, kde-pure, niri-pure,
  hyprland-pure, minimal, guided, desktop, laptop, core.
- **Known Noise**: committed JSONC beside the manifest, entries = regex,
  scope (source/phase optional), reason/ADR. Starts empty.
- **Driving**: persistent VM Harness flow (not `--testing`) + VM Agent
  Control. Destroy/reinstall reuses the harness's recreate path. The guided
  variant uses the existing guided flow. Encrypted boots unlocked via the
  existing Console Answerer path or equivalent serial answering.
- **New VM Agent Control verbs**: `key` (keyboard chord via `virsh
  send-key`), `mouse` (move/button/scroll via QEMU `input-send-event`),
  `net on|off` (guest link down/up via the libvirt interface), `pull`
  (fetch guest files/dirs to host). Existing verbs (`session`, `shot`,
  `exec`, `launch`, `logout`, `reboot`, `lock`) are reused.
- **Phases per variant** (tag every artifact): `install` → `boot1` →
  `sessions` (each compositor: login, collect, screenshot) → `probes-offline`
  → `probes-online` → `keybinds` (session-ending last, with recovery) →
  `timers+soak` → `boot2` (impermanence/persist/SOPS) → `upgrade` (`pacman
  -Syu` + reboot + collect). Emulated extras (suspend/resume, hibernate,
  test print to a host `ippeveprinter`) run inside probes.
- **Probe contract** (added to the program spec): each program may ship a
  guest-side probe script and a binds file.
  - Probe: runs in the guest as a given user (and root when relevant), with
    env for user/session/phase/online state; prints one line per check,
    `PASS|FAIL|SKIP <check-id> <message>`; exit code ignored in favour of
    lines; stderr captured.
  - Binds file: bind → expected observable effect (window class/app id
    appears, process exists, workspace/focus state, file created), plus a
    `session_ending` flag and optional recovery.
  - Desktop/compositor binds (niri, hyprland, KDE) live with the
    environment config they belong to, same contract.
- **Bind parsers**: one per config format (niri kdl, hyprland conf, KDE
  shortcuts, nvim keymaps via headless dump, kitty conf, zsh bindkey dump),
  output normalized `(source, chord, action)` rows.
- **Collectors** (guest → host, via `pull`): installer log (serial +
  on-disk), per boot `systemctl --failed` system/user, `journalctl -p
  warning -b` system/user, coredump list, kernel errors, compositor logs,
  probe outputs, screenshots.
- **Report**: classify raw lines → candidate Findings; drop Known Noise
  matches; normalize (strip timestamps, pids, addresses) for dedup key; merge
  across variants/boots with frequency counts; emit `findings.md`
  (grouped by phase then source; visual-review section with screenshot
  paths) and `findings.jsonl` (one Finding per line: id, key, variants,
  phase, source, program, adrs, excerpt, count/total, log paths, repro).
- **Run directory**: gitignored, under the installer tree, one timestamped
  folder per Audit Run, subfolder per variant then per phase.
- **Exit**: non-zero if any Finding (including coverage gaps and fatal
  variant aborts).

## Testing Decisions

- Good tests assert external behaviour of the two pure subcommands: given
  inputs (manifest/configs, or a run directory), the Findings produced. No
  assertions on internal helper names or intermediate files.
- **`check` seam** (bats, no VM): fixture manifests/host profiles; asserts
  valid resolution, rejection of bad patches, coverage-gap Findings
  (program without probe, feature without variant, bind without
  expectation), and each bind parser's normalized rows from fixture configs.
- **`report` seam** (bats, no VM): fixture run directories with synthetic
  install logs, journals, failed-unit lists, probe outputs, offline/online
  pairs; asserts Known Noise filtering, dedup across variants, frequency
  counts, runtime-fetch detection, fatal-abort Findings, `findings.md` /
  `findings.jsonl` shape, exit code.
- **VM Agent Control new verbs**: pure-function tests of command
  construction, like the existing agent-control bats.
- **Live**: only a real Audit Run tests `run` and the probes themselves; no
  bats for probes.
- Prior art: the matrix bats suite (sourced lib functions, committed-record
  drift guards), the agent-control bats, profile-validate bats.
- Bats files follow the directory mirror so Change-Targeted Runs pick them
  up; the coverage check guard joins the regular suite.

## Out of Scope

- Storage combinations (root fs, topology, per-group data-pool fs/enc):
  owned by the Combination Matrix.
- Parallel VMs.
- Any automatic trigger (pre-push, CI).
- Automated visual judgement of screenshots (left to the fixing agent).
- Fixing the Findings: a separate session after the first Audit Run.
- Real-hardware-only behaviour beyond what libvirt emulates (listed as
  `unverifiable`).

## Further Notes

- Order of work: build the whole tool (harness, collectors, report, check,
  every program/compositor probe and binds file), write the unverifiable
  list for review, then one full Audit Run → Findings → one fix session
  (each Finding fixed or moved to Known Noise with approval) → rerun until
  clean.
- ADR 0152 status moves from "design only" to implemented/VM-verified once
  a clean run lands.
- Commit this spec with `CONTEXT.md` + ADR 0152 after the tickets phase.
