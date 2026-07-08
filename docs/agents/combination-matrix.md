# Combination Matrix

Running notes for agents working on the Combination Matrix (ADR 0046) — the
two-tier "no menu-reachable install combination errors" testing. Entry point:
`.os/tools/matrix.sh` (`gen` / `emit <cell-id>` / `run`); generator/adapter
logic in `.os/lib/matrix/*.sh`; Tier-1 assembly bats under
`.os/tests/matrix/`.

The menu-derived, CI-enforced sync contract lands in slice 08. This file grows
with it; for now it records the environment gotchas that bite a live Tier-2
run.

## Tier-2 VM runs from an agent environment

Tier-2 (`matrix.sh run`) installs + boot-verifies a cell in a real VM via the
VM Harness. Two environment hazards, both independent of the matrix code:

- **archzfs ISO lag.** The ISO resolver picks the newest archived Arch ISO
  whose kernel archzfs ships a prebuilt module for. When archzfs trails the
  live kernel, the resolver returns an EMPTY ISO and the VM has no boot medium
  (`No bootable option or device`). Work around it by pinning a cached ISO:
  `ISO_URL_OVERRIDE=file:///path/to/archlinux-<date>-x86_64.iso`. The install
  then builds ZFS via the DKMS fallback against the ISO's kernel — slower, but
  it boots. Slice 05's profile synthesizer should own this ISO/oracle policy
  rather than leaving it as a manual override.

- **Local-repo serving.** The guest `git clone`s `REPO_URL` (default GitHub)
  for the installer code. To test unpushed local work, serve the repo at HEAD
  with `git daemon` and point `REPO_URL` at the libvirt gateway
  (`git://192.168.122.1/<repo>`). The daemon serves committed content only —
  the cell's Effective Config still reaches the guest inline via the profile's
  `.install` (the config seam), so uncommitted matrix code is not needed in the
  guest. In a sandboxed agent shell the daemon dies with its launching
  command's process-group teardown, so co-host `git daemon` and `matrix.sh run`
  in a single long-lived (background, sandbox-disabled) invocation.

See also [[dotfiles-vm-smoke-agent-context]] for the general VM-from-agent
constraints (one VM per job, 8 GiB RAM to avoid paru OOM, encrypted roots can't
headless boot-verify without the Console Answerer).
