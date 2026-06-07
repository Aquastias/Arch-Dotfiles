# Profile resolution + validation + vm.sh dry-run

Status: ready-for-agent

## Parent

`.scratch/vm-profile-harness/PRD.md`

## What to build

The pure spine of the VM Harness: read a JSONC **VM Profile** and turn it
into a full `install.jsonc`, with up-front validation — all without
libvirt.

A profile names its install config via exactly one source: a top-level
`host_profile` (resolved through the Pre-Install Picker's existing
template merge), an inline `install` object (a full Install Config), or
`install: "repo"` (use the committed `.os/install.jsonc`, hostname
patched). The resolver maps `hardware.disks` count to `/dev/sda…` by index
and takes the OS mode from the host template's pin, else `layout.mode`.

A validator rejects malformed profiles with a clear message (mirrors the
repo's fail-fast config validation): missing `name`; empty/invalid
`disks`; out-of-range `ram_mb`/`vcpus`/`timeouts`; zero or more than one
install source; a `host_profile` reference to a host with no Install
Template; bad `verify.mounts` (`dataset:/path`) or `verify.owned`
(`/path:user`) formats.

`vm.sh` gains enough skeleton to exercise this end-to-end: parse
`--profile <category>/<name>` and `--testing` (resolving the path against
`vm/profiles/` or `tests/vm/profiles/`), then a `--print-config` dry-run
that validates and emits the resolved `install.jsonc` to stdout.

Also add Install Templates for `arch-hyprland` and `arch-kde-hyprland`
(mirroring `arch-kde`'s: desktop + ashift) so the reference path resolves
for the desktop hosts and they become picker-installable. `arch-data`
stays template-less.

## Acceptance criteria

- [ ] `vm.sh --profile <p> --print-config` emits the resolved
      `install.jsonc` for a `host_profile`, an inline `install`, and a
      `"repo"` profile.
- [ ] `host_profile` resolution matches what `picker_assemble_config`
      produces for the same host (single + multi, pinned + unpinned mode).
- [ ] `"repo"` resolution is the committed `install.jsonc` with only
      `system.hostname` patched.
- [ ] Disk device paths derive from `hardware.disks` count (`/dev/sda`,
      `/dev/sdb`, …).
- [ ] `--testing` flips path resolution to `tests/vm/profiles/`.
- [ ] Validation rejects: no `name`, empty `disks`, two install sources,
      zero install sources, template-less `host_profile` reference,
      malformed `verify.mounts`/`verify.owned`, out-of-range numerics —
      each with a distinct, human-readable message.
- [ ] `arch-hyprland` and `arch-kde-hyprland` ship `install.template.jsonc`
      and now appear in `pick.sh`'s host enumeration.
- [ ] `profile.sh` and `profile-validate.sh` are unit-tested per behavior
      (resolution across all three sources; one test per validation rule).
      Prior art: `tests/picker.bats`, `tests/config/validation-*.bats`.
- [ ] `tests/run.sh` and `tests/shellcheck.sh` are green.

## Blocked by

None - can start immediately.
