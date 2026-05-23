Status: ready-for-agent

# Commons cleanup + ADR + audit lint + commons tests

## Parent

`.scratch/tests-and-commons-cleanup/PRD.md`

## What to build

Shrink the Shell Stdlib to fit reality and codify a convention for
growing it going forward. Four things land together in one PR so the
policy and the deletions cannot drift apart:

1. **Delete the 20 unused helpers** from `.os/lib/shell/*.sh`.
   Surviving functions: `print_status`, `check_root`,
   `send_user_notification`, `command_exists`, `package_installed`.
   The 9-module split stays on disk; `shell-stdlib.sh` still sources
   all nine. Modules that lose every function keep the shebang +
   existing header + a `# Reserved for future <domain> helpers —
   add functions here, add tests in commons-<domain>.bats.` line so
   a future reader sees them as scaffolding, not abandoned files.

2. **ADR 0011** at `docs/adr/0011-shell-commons-as-default.md`.
   Scope: `.os/programs/*/install.sh` only. Rule: prefer commons
   when a helper exists; new shared helpers land in
   `lib/shell/<module>.sh` with a matching test; do not redefine
   commons-named helpers locally. `lib/` and `tools/` explicitly
   out of scope.

3. **`tests/audit.sh` section 12** that greps every
   `programs/*/install.sh` for a local redefinition of any
   surviving commons helper (`print_status`, `check_root`,
   `send_user_notification`, `command_exists`, `package_installed`)
   and fails the audit on a match. Matches the existing audit
   sections' style.

4. **Per-module bats tests** for the surviving 5 functions:
   `commons-output.bats`, `commons-permissions.bats`,
   `commons-commands.bats`, `commons-packages.bats`,
   `commons-notifications.bats`. The `commons-` prefix avoids
   colliding with the existing `packages.bats` (which covers
   `lib/packages.sh`, not `lib/shell/packages.sh`).

`CONTEXT.md` is not touched — the existing `Shell Stdlib` glossary
entry remains accurate.

## Functions to delete

`string_contains`, `string_multiline_contains`,
`string_to_uppercase`, `string_strip_prefix`, `string_strip_suffix`,
`string_is_empty_or_null`, `string_substr`, `array_contains`,
`array_split`, `array_join`, `array_prepend`, `check_command`,
`command_output_contains`, `check_directory`, `directory_exists`,
`get_desktop_env`, `is_hyprland`, `is_kde`,
`make_env_bash_scripts_executable`, `make_executable_and_run`.

## Acceptance criteria

- [ ] All 20 listed functions removed; surviving 5 unchanged in
      behavior
- [ ] Empty modules read as `#!/usr/bin/env bash` + existing
      header + the *Reserved* line; no further content
- [ ] `shell-stdlib.sh` still sources all 9 modules (no facade
      change)
- [ ] ADR 0011 published with Status, Context, Decision,
      Consequences; scope and rule stated as in this issue
- [ ] `tests/audit.sh` section 12 added; passes today; fails when
      a duplicate is introduced (verify with a one-line test
      modification, then revert)
- [ ] 5 new `commons-<module>.bats` files exist, each exercising
      its module's surviving function(s) via external behavior
      only (stdout capture, exit code, stub argv)
- [ ] Full bats suite passes
- [ ] No callers in `programs/*/install.sh` broken by the
      deletions (zero callers existed pre-change; verify post-change)

## Blocked by

None - can start immediately
