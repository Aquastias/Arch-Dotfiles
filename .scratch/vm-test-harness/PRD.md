# PRD: VM Test Harness for Installer

Status: needs-triage
Category: enhancement

## Problem Statement

Testing the Arch Linux ZFS installer in `.os/` requires manually creating a VM in virt-manager, downloading the latest Arch ISO, mounting it, booting, copying scripts, editing configs, and watching the install run. Setup takes long enough that iterating on installer changes is painful. Single-disk layout is the only one currently working, so most testing targets that path. As the installer evolves, the team needs a fast, repeatable, automated test loop that produces a log file showing whether the install succeeded or where it failed.

## Solution

A host-side script `.os/setup-vm-for-testing.sh` that behaves like a user would behave manually: creates a VM in virt-manager (via `virt-install`), downloads the latest Arch ISO if not already cached, boots the VM into the live CD, configures the cloned repo's `install.jsonc`, runs `install.sh` unattended, and captures the entire installer output to `.os/testing-vm-logs`.

On re-runs, the existing VM is reused: the script forces it off and starts it again, the live CD boots fresh (overlayfs), cloud-init re-runs the same flow, and the log is overwritten. Re-running takes seconds to kick off and the only setup time is the install itself.

The script makes minimal additions to the installer — a single `--unattended` flag — so it can run without prompts.

## User Stories

1. As a maintainer, I want a one-command way to spin up a test VM and run the installer, so that I can iterate on installer changes without clicking through virt-manager.
2. As a maintainer, I want the script to download the latest Arch ISO automatically, so that I never have to manually fetch it.
3. As a maintainer, I want the ISO download skipped if the latest version is already in `~/Downloads/`, so that re-runs don't waste bandwidth.
4. As a maintainer, I want the test VM defined once and reused on subsequent runs, so that I don't pay VM-creation overhead repeatedly.
5. As a maintainer, I want a `--recreate` flag that wipes and recreates the VM, so that I can recover from a wedged disk state.
6. As a maintainer, I want the installer logs written to `.os/testing-vm-logs`, so that I can diff/grep them after a run.
7. As a maintainer, I want logs streamed during the run, not dumped at the end, so that I can `tail -F` and watch progress.
8. As a maintainer, I want the script to exit with the installer's exit code, so that I can chain it from CI or other scripts.
9. As a maintainer, I want a hard timeout (default 30 min, overridable via `VM_TEST_TIMEOUT`), so that a hung install doesn't block forever.
10. As a maintainer, I want the repo URL exposed as a top-level variable (`REPO_URL`), so that I can point it at a fork without editing logic.
11. As a maintainer, I want missing host dependencies (`virt-install`, `virsh`, `cloud-localds`) auto-installed via pacman, so that first-run setup doesn't require reading a checklist.
12. As a maintainer, I want a clear error if I'm not in the `libvirt` group, so that I know to run `usermod` and re-login rather than debug a permission failure.
13. As a maintainer, I want `libvirtd` auto-started if inactive, so that the script works after a fresh host reboot.
14. As a maintainer, I want the live CD to clone the repo fresh on every run, so that tests always reflect what is on the GitHub `main` branch.
15. As a maintainer, I want the hostname patched into `install.jsonc` automatically, so that the empty default doesn't trigger an interactive prompt.
16. As a maintainer, I want all interactive prompts in the installer bypassable via `--unattended`, so that the test harness never gets stuck on `read`.
17. As a maintainer, I want the VM spec hardcoded as constants at the top of the script (RAM, vCPU, disk size), so that I can edit them in one place without flag plumbing.
18. As a maintainer, I want the VM disk to be SATA `/dev/sda`, so that it matches the existing single-disk `install.jsonc` config.
19. As a maintainer, I want the ISO mounted as SATA CD-ROM, so that it matches the manual virt-manager flow I've been using.
20. As a maintainer, I want UEFI firmware (OVMF) used automatically, so that `systemd-boot` works without manual firmware switching.
21. As a maintainer, I want the boot order to be CD-ROM then HD, so that re-runs always return to the live CD without flag juggling.
22. As a maintainer, I want a sentinel line (`===INSTALLER-EXIT-N===`) emitted on the serial console, so that the host script knows when the install completed and with what exit code.
23. As a maintainer, I want the VM to power off automatically after the install finishes, so that the script can return promptly.
24. As a maintainer, I want test artifacts (`testing-vm-logs`, seed cache) gitignored, so that they don't pollute commits.
25. As a maintainer, I want the seed ISO regenerated every run, so that changes to the cloud-init template apply immediately without cache-busting.
26. As a contributor, I want the `--unattended` flag to be a permanent feature of the installer, so that future automation (CI, scripted reinstalls) can use it too.
27. As a maintainer, I want the script to print a clear failure if `virt-install` rejects `--boot uefi` (very old libvirt), so that I know to update libvirt rather than debug OVMF paths.
28. As a maintainer, I want the script's surface kept minimal (only `--recreate`, `--help`), so that the CLI doesn't bloat with knobs that should live as constants.

## Implementation Decisions

### Modules

- **ISO resolver** — deep module. Resolves the latest Arch ISO filename via `curl -sIL` against `archlinux.org/iso/latest/archlinux-x86_64.iso`, returns the path to a usable file in `~/Downloads/`. Downloads only if the resolved filename is not already present. No checksum verification (`pacstrap` will surface corruption).
- **Seed generator** — deep module. Renders a cloud-init `user-data` template with `REPO_URL` and test hostname, runs `cloud-localds` to produce `seed.iso`. Output path is in a per-run cache dir under `.os/.vm-test/`.
- **Sentinel watcher** — deep module. Tails a log file with a timeout; returns the integer N from `===INSTALLER-EXIT-N===`, or 124 on timeout. No libvirt dependency.
- **VM lifecycle wrapper** — shallow module. Wraps `virt-install`, `virsh destroy`, `virsh start`, `virsh undefine`. Glue around libvirt CLIs.
- **Dependency check** — shallow module. `command -v` + `sudo pacman -S --needed` for `virt-install`, `libvirt`, `cloud-image-utils`. Fails-fast with usermod hint if user is not in `libvirt` group; runs `sudo systemctl enable --now libvirtd` if inactive.
- **Top-level orchestrator** — `.os/setup-vm-for-testing.sh`. Composes the modules above.

### Installer changes (`.os/install.sh`, `.os/02-wipe.sh`, `.os/03-install.sh`, `.os/lib/config.sh`)

- `install.sh` parses `-y` / `--unattended`, exports `INSTALL_UNATTENDED=1`, forwards the flag to the numbered scripts.
- `02-wipe.sh`: when `INSTALL_UNATTENDED=1`, the disk-exclude prompt accepts the default (no exclusions) and the "WIPE" confirmation is skipped.
- `lib/config.sh::print_summary`: when `INSTALL_UNATTENDED=1`, the final `confirm "Proceed with installation?"` is skipped.
- Hostname stays prompted-when-empty; the test harness fills `install.jsonc` via `sed` before invoking the installer. No installer-side hostname change.

### Cloud-init contract

- archiso ships cloud-init NoCloud datasource enabled (default since 2024.04). Seed ISO is attached as a second SATA CD-ROM.
- `runcmd` redirects to `/dev/ttyS0`, clones the repo, `sed`s the hostname into `install.jsonc`, runs `install.sh --unattended`, emits the exit-code sentinel, and powers off.

### Log capture

- Host runs `virsh console --force` in the background piped to `tee` against `.os/testing-vm-logs`. File is overwritten per run (single-source-of-truth for the latest run; no timestamped history).
- The capture covers installer stdout/stderr only — kernel, init, and cloud-init startup logs go to tty0 by default in archiso and are not captured.

### VM lifecycle

- `destroy` + `start` is preferred over `reboot` for re-runs (faster, no graceful-shutdown hang on a half-mounted post-install state).
- `--recreate` does `virsh destroy && virsh undefine --remove-all-storage --nvram` then a fresh `virt-install`.
- Boot order is `cdrom,hd` — keeps the live CD reachable while the ISO is attached.

### VM spec (constants in script)

- 4096 MiB RAM, 2 vCPU, 40 GiB qcow2 SATA disk, default libvirt NAT, serial pty for `virsh console`, UEFI via `--boot uefi --osinfo archlinux`.

### Configuration surface

- Top of script: `REPO_URL`, `VM_NAME`, `VM_RAM_MB`, `VM_VCPUS`, `VM_DISK_GB`, `ISO_DIR`, `CACHE_DIR`, `LOG_FILE`, `TIMEOUT_SEC` (overridable via `VM_TEST_TIMEOUT`), `TEST_HOSTNAME`.
- CLI: `--recreate`, `--help`. No other flags.

### Gitignore

- `.os/.gitignore` adds `.vm-test/` and `testing-vm-logs`.

## Testing Decisions

### What makes a good test here

External behavior only: given a function's inputs (paths, environment, mocked subprocess output), the function returns the documented value or has the documented side effect. No assertions on internal helpers, log formatting, or progress messages. Tests live alongside the existing `.os/tests/` if present, using whatever runner is already in use; otherwise a minimal bash + assert pattern.

### Modules to test

- **ISO resolver** — given a fake `~/Downloads/` containing or not containing the resolved filename, with `curl` stubbed to return a known redirect, the resolver returns the right path and downloads only when needed. Covers the "skip if already cached" user story.
- **Seed generator** — given a repo URL and hostname, the generated `seed.iso` (or its underlying `user-data`) contains the expected substitutions. Verifies the cloud-init contract is what we think it is.
- **Sentinel watcher** — given a file with `===INSTALLER-EXIT-0===`, returns 0; with `===INSTALLER-EXIT-7===`, returns 7; with no sentinel and a 1-second timeout, returns 124. Verifies the host-side completion contract.

### Not tested

- VM lifecycle wrapper (libvirt CLI passthrough — implicitly covered by running the script).
- Dependency check (`pacman` interaction — manual smoke).
- Top-level orchestrator (composition — covered by running the script end-to-end).

### Prior art

`.os/tests/` if present in the repo provides the existing test pattern for installer-adjacent code. Match it.

## Out of Scope

- Multi-disk layout testing — only single-disk is currently working per the user's note.
- Verifying the installed system actually boots after install — the harness only verifies the installer ran; boot-from-disk validation is a separate concern.
- Hosting the test ISO somewhere other than `~/Downloads/`.
- Configurable VM specs via CLI flags — knobs live as constants at the top of the script.
- Branch/commit selection on the cloned repo — always tracks `main` of the configured `REPO_URL`.
- Testing uncommitted local changes — user must `git push` before testing.
- ISO checksum verification.
- Custom remastered ISOs.
- Capturing kernel / cloud-init startup logs (only installer stdout/stderr are captured).
- CI integration — script is exit-code clean enough to drop into CI later, but no GitHub Actions / similar setup in this PRD.

## Further Notes

- `--unattended` is a permanent installer feature, not test-harness scaffolding. It is small (one flag, three call sites) and pays off for any future automation.
- The `git push before testing` constraint is intentional: it forces the test harness to mirror the experience a real user has when cloning the repo, and avoids the trap of "passes locally but the pushed version is broken".
- Old Arch ISOs (pre-2024.04) lack cloud-init NoCloud support. If the script ever appears to do nothing after VM start, suspect a stale ISO before debugging cloud-init.
- The decision to log only installer output (not kernel / cloud-init) is a deliberate trade-off for simplicity; if a future failure mode happens before runcmd starts, the user falls back to the virt-manager GUI console.

## Comments

### Triage — split into agent-ready issues

> *This was generated by AI during triage.*

**Category:** enhancement
**State:** ready-for-human (PRD level — the implementation is delegated to the child issues below)

Split into five child issues, each `ready-for-agent`:

- `issues/01-installer-unattended-flag.md` — adds `-y` / `--unattended` to `install.sh` and call sites
- `issues/02-iso-resolver.md` — deep module: latest-Arch-ISO download with cache-hit skip
- `issues/03-seed-generator.md` — deep module: cloud-init NoCloud `seed.iso` builder
- `issues/04-sentinel-watcher.md` — deep module: tails the log for `===INSTALLER-EXIT-N===`
- `issues/05-vm-orchestrator.md` — `.os/setup-vm-for-testing.sh` composes the above

Issues 01–04 are unblocked and parallelisable. Issue 05 is blocked on all four. The three deep modules (02, 03, 04) carry bats tests; 01 is too small to test in isolation; 05 is verified by an end-to-end run on the user's host.
