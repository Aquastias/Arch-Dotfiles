# install.sh --profile end-to-end + unattended seam

Status: done

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Wire the two front-ends onto the one back-end. `install.sh --profile
<name>` becomes the user-facing interactive install: `load_profile` →
picker disk resolution → effective config in tmpfs → the existing
back-end that consumes an assembled config. The positional
`<config-file>` form remains the unattended seam the VM cloud-init seed
already injects, reused unchanged. The `host_profile` field is dropped
from the schema — the directory name / `--profile` arg is the identity.

## Acceptance criteria

- [x] `install.sh --profile <name>` runs a full interactive install via
      load_profile → picker → tmpfs effective config → back-end.
- [x] The positional `<config-file>` form still works as the unattended
      seam (the VM seed path).
- [x] The `host_profile` field is removed from the schema and no longer
      read.
- [x] No committed assembled config is required; the effective config is
      transient.
- [x] Verified end-to-end by a VM install via `--profile`.

## Blocked by

- `.scratch/unified-host-profile/issues/02-picker-disk-group.md`

## Comments

### Agent (TDD)

Implemented behind one back-end; positional seam unchanged.

- `host_profile` dropped from the closed schema + accessor table
  (drift guard green); `RESOLVED_HOST_PROFILE` ← hostname.
- `picker_assemble_config` / `picker_assign_disks` emit no
  `host_profile`.
- New pure seam `assemble_profile_config <name> <assignment>`
  (load_profile + picker_assign_disks + dirname hostname fallback),
  bats-tested in `tests/config/profile-loader.bats`.
- `install.sh --profile` wired: validate → load → disk pick → tmpfs
  → 01/02/03. fzf glue not bats-tested (repo `pick.sh` doctrine).

Full suite green (1036/1036).

AC5 (VM e2e) deferred to the human gate: it needs a migrated
`profile.jsonc` with a declared layout — none exist yet (all
synthesized via the scaffold). The disk→group picker fully
exercises once `arch-data` is migrated (issue 08). Hence
`ready-for-human`.

### Agent verification (Claude) — 2026-06-10

AC5 substantially met for single-pool hosts. VM runs of `single/plain`
(`install:"repo"` → the default host profile) and `desktop/kde`
(`host_profile: arch-kde`) both assemble the effective config through
`load_profile` → `assemble_profile_config` and install to exit 0 / boot
into KDE. The unattended positional seam is what the VM seed injects, so
the back-end is exercised end-to-end. The interactive `--profile` fzf
picker can't run unattended in a VM, and its **multi-pool** disk→group
assignment is unbuilt (gap #5, see issue 08) — so a multi-data-pool host
(arch-data) is not yet installable via `--profile`. Fixed en route: the
`install:"repo"`→default regression and the Profiles Runner reading the
legacy `config.jsonc` instead of the assembled effective config.

### AC5 closed — `--profile` path VM-verified end-to-end — 2026-06-11

The last AC is met. The VM harness `host_profile` path is the programmatic
`--profile` install — the same `validate_profile` → `load_profile` →
`assemble_profile_config` → 01/02/03 back-end, only the fzf disk-pick is
replaced by the VM disk list. Verified end-to-end (install +
`INSTALLER-EXIT-0` + first-boot sentinel) for both pool shapes:
- **multi-data-pool**: `data-pools/from-profile` (host_profile arch-data) —
  per-group slicing rpool→sda / tank0→sdb / tank1→mirror(sdc,sdd), `vm-data`
  owns the /data pools (issue 12).
- **single-pool**: `env/kde` / `env/hyprland` / `env/kde-hyprland`
  (host_profile arch-kde/-hyprland/-kde-hyprland) all boot into their DE.

The only piece not headless-testable is the literal interactive
`install.sh --profile` fzf disk-pick (repo pick.sh doctrine excludes fzf
glue from automated tests); its producer `picker_build_assignment` is the
same code the verified harness path runs, and is bats-covered
(`tests/picker-assign.bats`). Closing.
