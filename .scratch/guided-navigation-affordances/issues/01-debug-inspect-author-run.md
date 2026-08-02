# --debug inspect/author run

Status: ready-for-agent

## Parent

`.scratch/guided-navigation-affordances/PRD.md`

## What to build

`install.sh --debug` turns any front-end into inspect/author-only. It skips the
full-toolchain preflight — ensuring only the front-end tools (`jq`, plus `fzf`
when an interactive front-end will run) so the menu still launches — and
**withholds the install**: the numbered bootstrap/wipe/install phases never
execute, so no disk is touched. The guided menu and its previews, the
`--profile` disk picker, and Save Profile / Export Config all still work. Plain
`install.sh` (no `--debug`) on the live CD stays fully preflight-guarded and
installs as before. The flag is global — honoured by the guided, `--profile`,
and positional-config front-ends alike.

The decision "given the parsed flags, which preflight tier applies and does this
run install?" lives in one new pure resolver that install.sh calls, so the
"front-end-tools-only, never install" guarantee is unit-testable without running
the installer. The existing guided "terminal action that is not install"
early-exit (rc 64) is the model for withholding the phases.

The flag keeps the name `--debug` even though it means "skip install", not
"verbose logging"; document that meaning at the flag site.

## Acceptance criteria

- [ ] `install.sh --debug` launches the guided menu on a box lacking the install
      toolchain, without attempting to pacman-install `pacstrap`/`mdadm`/etc.
- [ ] Under `--debug`, bootstrap/wipe/install phases never run and no disk is
      touched, on all three front-ends (guided, `--profile`, positional config).
- [ ] Under `--debug`, Save Profile and Export Config still write their
      artifacts, and the `--profile` disk picker still runs for inspection.
- [ ] `jq` (and `fzf` for interactive front-ends) are still ensured under
      `--debug`, so the menu can launch.
- [ ] Without `--debug`, the full-toolchain preflight and install run exactly as
      today (no behaviour change on the live CD).
- [ ] Pure resolver maps parsed flags → (preflight tier, install-or-not); it is
      unit-tested table-style (prior art: `tests/preflight.bats`) covering
      `--debug` and each non-debug front-end, asserting the install-withheld
      decision without executing the installer.
- [ ] The flag site documents that `--debug` skips install, not logging.

## Blocked by

- None — can start immediately.
