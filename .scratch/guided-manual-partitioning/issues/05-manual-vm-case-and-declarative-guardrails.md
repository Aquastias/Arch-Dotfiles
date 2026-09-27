# 05 — End-to-end VM case + declarative-path guardrails

**What to build:** The proof and the fences. A full manual-partitioning VM case
drives the whole path — scripted `cfdisk` seed → assignment → install → verified
boot — so the interactive escape hatch is proven to produce a usable machine. And
the guardrails that keep manual out of the reproducible paths: `kind: manual` is
rejected on the `--profile` Pre-Install Picker and the unattended `install.sh
<config-file>` path, since a hand-drawn table cannot be replayed from a committed
file.

**Blocked by:** 04.

**Status:** done

- [ ] A manual VM matrix case (scripted partition table standing in for the
      operator's `cfdisk`) assigns, installs, and boots; registered on the
      Combination Matrix as a `disk_config.kind: manual` axis value.
- [x] The `--profile` Pre-Install Picker rejects a config whose
      `disk_config.kind` is `manual`, with an actionable message.
- [x] The unattended `install.sh <config-file>` path rejects `kind: manual`
      likewise.
- [x] The rejection guards are covered headless in bats; the boot is verified in
      the VM via the existing harness / `vm/vm-pool-verify.bats` prior art.

## Comments

- 2026-09-27 audit: efa5b5a shipped the --profile / unattended rejection guards
  (bats). No manual VM matrix case exists — reopened for that.

- 2026-09-27 audit: 0a14fa0 (guided_manual seed + _guided_edit_manual replay),
  3b4b196. VM run 2026-09-27: tests/vm/profiles/single/guided-manual.jsonc
  (vm.sh --guided, local repo) — sgdisk scripts ESP+swap+root in place of
  cfdisk, the replay's manual_disk= scans and assigns it, the review says
  'MANUAL … (no wipe)', 02-wipe resolves no targets, / on sda3 ext4 and the ESP
  on sda1 mount, the install exits 0 and the installed system reaches
  FIRSTBOOT-OK. The run exposed and fixed three bugs: the wipe would have erased
  the table (f8b02ab), the ESP mount failed without the vfat module (2287385),
  and the zfs-auto-snapshot Backup default pulled ZFS from the AUR on a ZFS-less
  install (2f3b564). The 'registered on the Combination Matrix as an axis value'
  part stays unticked: the matrix drives the unattended config path, which
  rejects kind: manual by design, so the case lives as a guided cell instead.
