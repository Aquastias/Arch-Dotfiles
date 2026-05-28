# ADR 0010: Pre-Install Picker as a separate tool, not a flag on install.sh

## Status
Accepted. Superseded in part by ADR-0020 (Host Profile decoupled from hostname).

## Context
`install.sh` is a declarative config-applier: every input lives in
`install.jsonc` and the host/user configs, so the same configs always
produce the same install (ADR-0002, ADR-0003). Two facts can't be known
until the operator is standing in front of the target machine on the
live CD:

- which host config to apply (sets hostname)
- which `/dev/disk/by-id/*` device(s) to install onto

Every other field — locale, timezone, keymap, bootloader,
`environment.desktop`, `environment.gpu`, `options.encryption`,
`options.impermanence.*`, ZFS pool/dataset names — is a property of the
machine, not of any particular install run, and belongs in a committed
per-host template.

A live-CD picker is the natural place to resolve the two unknowns and
write `install.jsonc`. The question is where the picker lives.

## Decision
The picker is a separate tool at `.os/tools/pick.sh`, parallel to
`save-pkglist.sh` and `impermanence.sh`. `install.sh` stays a pure
applier with no interactive branches.

- `pick.sh` self-installs `fzf` and `jq`, lists hosts that ship an
  `install.template.jsonc`, prompts for one host + the install target
  disks (mode-then-disks against the Layout Module's single/mirror/
  raidz seam), loads every other field from the chosen host's Install
  Template, validates the result via `lib/install-config.sh`, then
  shows a review screen with `[w]rite & install / [w]rite only /
  [e]dit / [a]bort`.
- `install.sh` reads `.os/install.jsonc` unchanged — it has no idea
  the picker exists.
- Workflow on the live CD becomes: clone repo → `./pick.sh` → (review
  the committed `install.jsonc`) → `./install.sh`. The picker's
  "write & install" option fuses the last two steps for the impatient.

## Considered alternatives
**Flag on `install.sh` (e.g. `install.sh --interactive`).** Preserves
the Single Entry Point promise as a single binary, but folds an
interactive code path into the installer that has to be conditionally
skipped in VM tests and unattended installs. Mixes config-build with
config-apply in one script.

**Auto-fallback when `install.jsonc` is missing.** Nicer first-run UX,
but a missing or syntactically broken config silently flips the
installer into interactive mode in exactly the contexts where you
don't want it (CI runs, VM tests, scripted reinstalls). Fail-loud is
better here.

## Consequences
- Single Entry Point (CONTEXT.md) is interpreted as "one user-facing
  install command," not "one script in the repo." Tools have always
  lived beside the installer; the picker joins them.
- `install.sh` remains trivially testable — VM tests never invoke the
  picker, and the install path has no interactive branch to mock.
- The set of pickable hosts is gated on `install.template.jsonc`
  presence. Hosts without a template are invisible to the picker but
  still installable by hand-editing `install.jsonc` — the picker is a
  convenience, not a gatekeeper.
- Per-host commitment to bootloader/DE/GPU/encryption/impermanence
  lives in `install.template.jsonc`. Re-picking those per install
  requires editing the template, not flipping a wizard prompt — which
  is the right friction for properties of the machine.
