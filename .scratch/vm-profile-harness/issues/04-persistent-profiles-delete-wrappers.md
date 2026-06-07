# Author persistent profiles + delete prod wrappers

Status: done

## Parent

`.scratch/vm-profile-harness/PRD.md`

## What to build

Author the full persistent VM Profile inventory and retire the prod
wrapper scripts now that the persistent flow is profile-driven (issue 02).

Profiles, as JSONC under `vm/profiles/`, grouped into Profile Categories:

- `desktop/kde.jsonc` → `host_profile: arch-kde`
- `desktop/hyprland.jsonc` → `host_profile: arch-hyprland`
- `desktop/kde-hyprland.jsonc` → `host_profile: arch-kde-hyprland`
- `headless/secure.jsonc` → `host_profile: arch-secure`, with the
  `fixtures: ["fixtures/key.age"]` staging the Test Age Key.

Each carries its `hardware` block (disk sizes / RAM / vCPUs matching
today's scripts) and any explanatory header comments lifted from the
script it replaces (the secure profile keeps its post-reboot verification
notes).

Delete the 4 `vm/vm-*.sh` wrappers. Rewrite `vm/README.md` to document
`vm.sh --profile <category>/<name>` (quick start, flavors table by
profile, options, env overrides). Leave ADRs 0019/0028 untouched.

## Acceptance criteria

- [ ] `vm/profiles/{desktop/kde,desktop/hyprland,desktop/kde-hyprland,
      headless/secure}.jsonc` exist and each validates + resolves via
      `vm.sh --print-config`.
- [ ] `headless/secure` stages `key.age` and resolves the SOPS +
      impermanence + encryption + mirror config of `arch-secure`.
- [ ] The 4 `vm/vm-*.sh` scripts are deleted.
- [ ] `vm/README.md` documents the `vm.sh --profile` workflow; no stale
      references to the deleted scripts remain in it.
- [ ] `tests/run.sh` and `tests/shellcheck.sh` are green.

## Blocked by

- `.scratch/vm-profile-harness/issues/02-persistent-flow-core.md`
