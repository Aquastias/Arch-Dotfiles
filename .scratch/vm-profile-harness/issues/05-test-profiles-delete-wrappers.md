# Author test profiles + delete test wrappers

Status: ready-for-agent

## Parent

`.scratch/vm-profile-harness/PRD.md`

## What to build

Author the full test VM Profile inventory and retire the `testing-*.sh`
wrappers now that the test flow is profile-driven (issue 03).

Profiles, as JSONC under `tests/vm/profiles/`, grouped by the install path
they exercise:

- `single/plain.jsonc`, `single/dirty-cache.jsonc` → `install: "repo"`
  (dirty-cache adds `verify.dirty_cache: true`).
- `multi/{mirror,stripe,none,mirror-storage}.jsonc` → inline `install`.
- `impermanence/{single,mirror,kde-encrypted,kde-sops}.jsonc` → inline.
- `data-pools/{plain,reorder}.jsonc` → inline, with `host_profile:
  arch-data` *inside* the install block (selects the `vm-data` user for
  pool-owners); `reorder` sets `verify.reorder_boot_disks`, `verify.by_id`,
  `verify.owned`, plus `pools`/`mounts`.
- `env/{kde,hyprland,kde-hyprland}.jsonc` → `host_profile: arch-kde /
  arch-hyprland / arch-kde-hyprland` (boot-verify the real desktop hosts).

Each carries `hardware`, optional `timeouts` for slow cases, and (where
applicable) a `verify` block migrated from the script's `VM_VERIFY_*`
constants. Lift the explanatory header prose into JSONC comments.

Delete the 14 `tests/vm/testing-*.sh` wrappers. Rewrite the VM section of
`.os/README.md` to document `vm.sh --testing --profile <category>/<name>`.

## Acceptance criteria

- [ ] All test profiles exist under `tests/vm/profiles/<category>/` and
      each validates + resolves via `vm.sh --testing --print-config`.
- [ ] `single/*` use `"repo"`; `multi/*` and `impermanence/*` inline;
      `data-pools/*` inline with `host_profile: arch-data` inside.
- [ ] `env/*` reference the desktop host profiles.
- [ ] `verify` blocks reproduce each script's prior `VM_VERIFY_*` /
      `VERIFY_BOOT` / `DIRTY_CACHE` / reorder expectations.
- [ ] The 14 `testing-*.sh` scripts are deleted.
- [ ] `.os/README.md` VM section documents the new workflow with no stale
      script references.
- [ ] `tests/run.sh` and `tests/shellcheck.sh` are green.

## Blocked by

- `.scratch/vm-profile-harness/issues/03-test-flow-helper-relocation.md`
