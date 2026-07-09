# 07 — VM seam: bound install boots

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-disk-binding-custom-layouts/PRD.md`

## What to build

Prove the on-target bound path installs and boots a real system end-to-end.
Because In-Menu Disk Binding is interactive-only, add a scriptable seam so a VM
can exercise the bound assignment path without a tty.

- **Replay `devices[]` injection** — `--guided` replay gains a per-pool device
  answer form that injects bound disks into the Config State, so the bound
  assignment path (slice 04) runs from an answers file rather than the summed
  post-menu pick.
- **One bound cell** — install a bound multi-disk layout in a VM through the
  existing config seam (`vm.sh --testing --verify-boot`) and assert
  `INSTALLER-EXIT-0` + the first-boot sentinel, confirming the disks bound in the
  answers file became the installed pools and the system boots.

Prior art: the combination-matrix Tier-2 VM cells and `seed-generator-guided`
tests.

## Acceptance criteria

- [ ] A `--guided` answers file can specify each pool's bound by-id disks, and the
      resulting Config State carries them as `devices[]` (asserted at the pure /
      seed seam).
- [ ] A replayed bound layout resolves through the slice-04 assignment path (no
      summed flat pick) into a valid Effective Config.
- [ ] One bound multi-disk cell installs in a VM and reports PASS on
      `INSTALLER-EXIT-0` + `===FIRSTBOOT-OK===`.
- [ ] Full existing bats suite stays green.

## Blocked by

- 04 — Flatten + assignment build (a bound layout installs).
