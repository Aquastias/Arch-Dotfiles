# VM provisioning: one profile-driven harness + test-folder reorg

Status: done

Glossary: VM Profile, VM Harness, Profile Category, Host Profile, Install
Template, Install Config, Pre-Install Picker, Host Config, Disk Wipe,
Standalone Data Pool, Storage Group, Pool Owners.

## Problem Statement

VM provisioning is a sprawl of near-identical scripts. Four persistent
`vm/vm-*.sh` and ~14 `tests/vm/testing-*.sh` each set a couple of VM vars
and inline a full `install.jsonc` that only differs by a few fields —
config that is *already* duplicated into the `hosts/vm/*` Install
Templates. Two harnesses (`vm/_harness.sh`, `tests/vm/_harness.sh`)
diverge yet share `_harness-core.sh`, so behaviour lives in two places.
Adding a VM flavour or a test permutation means copy-pasting a whole
script. The test suite is half-migrated: `tests/wipe/` coexists with
stale top-level `wipe-*.bats` (one an outright duplicate), `chroot-*` and
`vm-*` bats sit flat while `lib/` is foldered by subsystem. There is no
single, discoverable way to say "build me this VM."

## Solution

One profile-driven harness. `vm/vm.sh --profile <category>/<name>` reads a
**VM Profile** — a JSONC file describing one VM — and provisions it.
`--testing` selects the disposable test flow (headless, serial capture,
sentinel/exit-code, boot-verify); the default is the persistent flow
(spice, reboots into the installed system for interactive use). The same
`--profile` resolves against `vm/profiles/` normally and
`tests/vm/profiles/` under `--testing`; a test profile run *without*
`--testing` yields a persistent debug VM of that exact case.

A VM Profile names its install config via exactly one source: a
`host_profile` reference (resolved through the picker's existing Install
Template merge — one source of truth), an inline `install` block (for
test-only permutations with no real host), or `"install": "repo"` (smoke
test the committed default). Profiles are grouped into **Profile
Categories** (subfolders). All harness code consolidates under `vm/lib/`;
`tests/vm/` keeps only profiles and run artifacts. The 18 wrapper scripts
are deleted. The test tree finishes mirroring `lib/`.

## User Stories

1. As a dev, I want one VM script that takes a profile, so that I stop
   copy-pasting a whole script per flavour.
2. As a dev, I want VM Profiles as JSONC data files, so that adding a VM
   is authoring data, not code.
3. As a dev, I want `vm.sh --profile desktop/kde` to build the KDE VM, so
   that the entry point is one discoverable command.
4. As a dev, I want `--testing` to run the existing automated test flow,
   so that no regression-testing capability is lost in the unification.
5. As a dev, I want a test profile to build as a persistent VM when I omit
   `--testing`, so that I can interactively debug a failing test case.
6. As a dev, I want a profile to reference a `host_profile`, so that the
   VM exercises the real host's Install Template instead of a copy.
7. As a dev, I want a profile to inline a full `install` block, so that I
   can express an install permutation that is not a real machine.
8. As a dev, I want `"install": "repo"`, so that a VM run still smoke-tests
   the committed `install.jsonc` installs.
9. As a dev, I want profiles grouped into categories, so that related VMs
   are organised (`desktop/`, `headless/`, `single/`, `multi/`,
   `data-pools/`, `impermanence/`, `env/`).
10. As a dev, I want persistent profiles under `vm/profiles/` and test
    profiles under `tests/vm/profiles/`, so that the two purposes are
    physically separated.
11. As a dev, I want a profile to declare its hardware (disk sizes, RAM,
    vCPUs), so that VM geometry travels with the profile.
12. As a dev, I want disk device paths derived from disk count
    (`/dev/sda`, `/dev/sdb`, …), so that I only specify sizes.
13. As a dev, I want a `layout.mode` field used only when the host
    template does not pin layout, so that pinned hosts (e.g. `arch-secure`)
    are not double-specified.
14. As a dev, I want a test profile to carry `verify` expectations (boot,
    by-id, reorder, dirty-cache, pools, mounts, owned), so that boot-time
    assertions live with the case.
15. As a dev, I want optional staged `fixtures` (e.g. `key.age`), so that
    the secure profile's age key is served during install.
16. As a dev, I want optional per-profile `timeouts`, so that slow configs
    (encryption + impermanence, 4-disk raidz2) get more time without a
    global override.
17. As a dev, I want env vars to still override timeouts and hardware at
    run time, so that a one-off slow host needs no profile edit.
18. As a dev, I want the harness to validate the profile up front with a
    clear error, so that a malformed profile fails fast, not mid-install.
19. As a dev, I want a profile that sets two install sources to be
    rejected, so that the xor invariant is enforced.
20. As a dev, I want a `host_profile` reference to a template-less host to
    be rejected with a clear message, so that the failure is legible.
21. As a dev, I want `arch-hyprland` and `arch-kde-hyprland` to ship
    Install Templates, so that env-* profiles can reference them and they
    become picker-installable on real hardware.
22. As an operator, I want to picker-install Hyprland on real hardware,
    so that the Hyprland host is not silently absent from `pick.sh`.
23. As a dev, I want the persistent KDE/Hyprland/KDE+Hyprland profiles to
    reference their host profiles, so that prod VMs mirror real installs.
24. As a dev, I want the secure profile to reference `arch-secure`, so that
    SOPS + impermanence + encryption + mirror are tested as the real host.
25. As a dev, I want the `multi-data-pools` test to keep its inline config
    with `host_profile: arch-data` inside, so that pool-owners resolves the
    `vm-data` user without `arch-data` needing a template.
26. As a dev, I want the env-* tests to reference `arch-kde` /
    `arch-hyprland` / `arch-kde-hyprland`, so that they boot-verify the
    real desktop host profiles end-to-end.
27. As a dev, I want all the OS-topology permutation tests (mirror,
    stripe, none, mirror-storage, mirror-impermanent) as inline profiles,
    so that regression fixtures are explicit and immune to host edits.
28. As a dev, I want the single-disk and dirty-cache tests as `"repo"`
    profiles, so that the committed default config stays under test.
29. As a dev, I want all harness code under `vm/lib/`, so that the prod
    entry point never depends on a `tests/` path.
30. As a dev, I want the test-only helpers (sentinel-watcher,
    seed-generator, vm-pool-verify, reorder-disks) moved to `vm/lib/`, so
    that the consolidated harness owns them.
31. As a dev, I want the 18 wrapper scripts deleted, so that the
    consolidation is real and not shadowed by forwarders.
32. As a dev, I want both READMEs rewritten to document `vm.sh --profile`,
    so that the docs match the new entry point.
33. As a dev, I want the test tree to mirror `lib/`, so that a test's home
    is predictable from the module it covers.
34. As a dev, I want the wipe tests consolidated under `tests/wipe/` with
    the stale top-level duplicates removed, so that wipe coverage is in one
    place.
35. As a dev, I want `chroot-*` bats under `tests/chroot/` and the
    `lib/shell/`-backed `commons-*` bats under `tests/shell/`, so that the
    folder mirrors the lib subsystem.
36. As a dev, I want `commons-part-name.bats` to stay flat, so that a test
    of flat `lib/common.sh` is not misfiled under `tests/shell/`.
37. As a dev, I want the desktop-adapter bats (`kde-adapter`,
    `hyprland-adapter`, `environment-runner`) under `tests/extras/`, so
    that adapter tests track `extras/`.
38. As a dev, I want all `vm-*.bats` under `tests/vm/`, so that harness
    unit tests sit beside the harness's profiles and artifacts.
39. As a dev, I want the relocated harness bats rewired to the new paths,
    so that the suite stays green after the move.
40. As a dev, I want `tests/run.sh` to keep discovering every bats
    recursively, so that foldering needs no runner change.
41. As a dev, I want `profile.sh` resolution unit-tested across all three
    sources, so that the assembled `install.jsonc` is provably correct.
42. As a dev, I want `profile-validate.sh` unit-tested per rule, so that
    every footgun has a guarding test.

## Implementation Decisions

- **VM Profile (data, JSONC).** Top-level keys: `name` (libvirt domain);
  `hardware` (`disks` int-GiB array, `ram_mb`, `vcpus`); exactly one
  install source — top-level `host_profile` (string) **xor** `install`
  (object: a full Install Config) **xor** `install: "repo"` (string
  sentinel); optional `layout` (`mode`, used only when the referenced
  template does not pin layout); optional `fixtures` (array of repo-relative
  file paths staged into the cache dir); optional `timeouts`
  (`install`, `boot` seconds); and, for test profiles, `verify` (`boot`,
  `by_id`, `reorder_boot_disks`, `dirty_cache` booleans; `pools`, `mounts`
  as `dataset:/mount`, `owned` as `/mount:user` arrays).

- **`vm/lib/profile.sh` (deep, pure).** Loads + strips a JSONC profile and
  resolves the install config to full `install.jsonc` text. `host_profile`
  → `picker_load_template` + `picker_assemble_config` (disks mapped to
  `/dev/sda…` by index; mode from the template pin, else `layout.mode`);
  inline `install` → emitted verbatim; `"repo"` → committed
  `.os/install.jsonc` with `system.hostname` patched from the profile.
  Reuses `lib/picker.sh` and `lib/jsonc.sh` unchanged. No libvirt, no TTY.

- **`vm/lib/profile-validate.sh` (deep, pure).** Full schema validation
  mirroring `lib/config/validation.sh` scope: `name` present; `hardware.disks`
  a non-empty array of positive ints; `ram_mb`/`vcpus` positive ints in
  sane ranges; exactly one install source; a `host_profile` reference names
  a host that ships `install.template.jsonc`; `timeouts` positive ints;
  `verify.mounts` match `dataset:/path` and `verify.owned` match
  `/path:user`. Returns 0 silently or non-zero with a human-readable
  message. Called by `vm.sh` before any work.

- **`vm/lib/core.sh` (orchestration).** Absorbs `_harness-core.sh` plus the
  shared parts of both old harnesses: dependency checks, libvirt
  group/daemon ensure, ISO resolution (pinned override + archzfs-compatible),
  VM state predicates, domain create/boot, storage-pool refresh, and
  fixture staging. Per-flow `virt-install` flag differences are supplied by
  the flow module.

- **`vm/lib/flow-persistent.sh`.** Spice graphics, minimal HTTP run-script
  served on the libvirt gateway, `send-key` console typing, wait-for-IP /
  wait-for-SSH, wait-for-poweroff, then reboot into the installed system.

- **`vm/lib/flow-test.sh`.** Headless graphics, cloud-init `runcmd` seed
  (via `seed-generator.sh`), serial console capture, sentinel-watcher wait,
  installer exit-code propagation (0 / 124 timeout / 125 boot-fail), and
  opt-in boot-verify (eject cdroms, optional disk reorder, dirty-cache,
  pool-verify expectations from the profile `verify` block).

- **`vm/vm.sh` (thin entry).** Parses `--profile`, `--testing`,
  `--recreate`, `--verify-boot`, `--help`. Resolves `--profile X/Y` to
  `vm/profiles/X/Y.jsonc` or, under `--testing`, `tests/vm/profiles/X/Y.jsonc`.
  Validates, then sources + dispatches to the selected flow.

- **Override precedence.** Profile values are defaults; matching env vars
  still win at run time. Timeouts resolve env > profile > flow default.

- **Relocations.** `sentinel-watcher.sh`, `seed-generator.sh`,
  `vm-pool-verify.sh`, `reorder-disks.py` move from `tests/vm/lib/` to
  `vm/lib/`. `_harness-core.sh`, `vm/_harness.sh`, `tests/vm/_harness.sh`
  are removed (folded into core + flows).

- **New host Install Templates.** `hosts/vm/arch-hyprland` and
  `hosts/vm/arch-kde-hyprland` gain `install.template.jsonc` mirroring
  `arch-kde`'s (desktop + ashift), making them referenceable and
  picker-installable. `arch-data` stays template-less.

- **Profile inventory (target).** Persistent: `desktop/{kde,hyprland,
  kde-hyprland}` (reference host profiles), `headless/secure` (reference
  `arch-secure`). Test: `single/{plain,dirty-cache}` (`"repo"`),
  `multi/{mirror,stripe,none,mirror-storage}` (inline),
  `impermanence/{single,mirror,kde-encrypted,kde-sops}` (inline),
  `data-pools/{plain,reorder}` (inline, `host_profile: arch-data` inside),
  `env/{kde,hyprland,kde-hyprland}` (reference host profiles).

- **Test-tree taxonomy.** A test lives in `tests/<sub>/` iff `lib/` ships a
  matching `lib/<sub>/`; otherwise it stays flat. Moves: `wipe-*` →
  `tests/wipe/` (drop the stale top-level four, dedupe the prior-state
  overlap), `chroot-*` → `tests/chroot/`, `lib/shell/`-backed `commons-*`
  → `tests/shell/<module>.bats` (renamed 1:1; `commons-part-name.bats`
  stays flat), adapters → `tests/extras/`, `vm-*.bats` → `tests/vm/`.
  Relocated bats are rewired to the new source paths.

- **Cleanup.** Delete the 18 wrapper scripts. Rewrite `.os/vm/README.md`
  and the VM section of `.os/README.md` to document `vm.sh --profile`.
  Leave ADRs 0019 / 0028 untouched (point-in-time record).

- **Recorded in** ADR 0035 (profile-driven harness) and CONTEXT.md (VM
  Profile, VM Harness, Profile Category, plus the `host_profile` two-layer
  flagged ambiguity).

## Testing Decisions

- A good test asserts external behaviour, not implementation. For the pure
  modules that means: given a profile JSON (and, for the reference path, the
  on-disk templates), assert the resolved `install.jsonc` and the
  validator's accept/reject + message — never internal helper calls.

- **`tests/vm/profile.bats` (new).** Resolution across all three sources:
  `host_profile` produces the same config the picker assembles (single +
  multi, pinned + unpinned mode, disk-count → `/dev/sdX`); inline emits
  verbatim; `"repo"` patches only the hostname. Prior art: `tests/picker.bats`
  (drives `picker_assemble_config`), `tests/config/install-config.bats`.

- **`tests/vm/profile-validate.bats` (new).** One test per rule: missing
  `name`; empty/invalid `disks`; both install sources; zero sources;
  template-less `host_profile`; bad `verify.mounts` / `verify.owned`
  formats; out-of-range `timeouts`. Prior art: `tests/picker.bats`
  (`picker_validate_layout`), `tests/config/validation-*.bats`.

- **Relocated helper bats (move + rewire, coverage preserved):**
  `sentinel-watcher`, `seed-generator`, `vm-pool-verify`, `vm-reorder-disks`,
  `vm-harness-fixtures` (re-point at the fixture-staging fn now in
  `core.sh`), `vm-fixtures-regenerate` (fix relative path only).

- **Flow / core integration.** `core.sh`, `flow-persistent.sh`,
  `flow-test.sh` are the libvirt harness itself; they are exercised by real
  VM runs (the profiles), not unit tests.

- The whole suite stays runnable via `tests/run.sh` (recursive bats
  discovery — no runner change needed). `tests/shellcheck.sh` must stay
  green over the new `vm/lib/` scripts.

## Out of Scope

- Multi-kernel, non-libvirt backends, or non-Arch guests.
- Changing the installer (`install.sh`) or any install-time behaviour. This
  is purely how VMs are provisioned and how tests are organised.
- Rewriting ADRs 0019 / 0028 to drop old script names.
- A `tests/tools/` folder or moving non-`lib/`-backed flat tests beyond the
  decided set.
- Parameterising disk *device* mapping beyond index order, or per-disk
  buses other than the current SATA default.
- CI wiring to run VM integration profiles automatically (they remain
  manual, as today).

## Further Notes

- The `host_profile` reference path depends entirely on the existing
  `lib/picker.sh` pure functions; no picker change is needed beyond the two
  new templates it will now enumerate.
- A test profile run without `--testing` is the supported interactive
  debug path — keep the flows behaviourally consistent up to the
  observe/teardown divergence.
- Watch the lockstep gotcha: relocating `lib/shell`-backed tests and the
  harness helpers must update every `source=`/`BASH_SOURCE`-relative path
  and shellcheck `# shellcheck source=` directive in the moved files.
