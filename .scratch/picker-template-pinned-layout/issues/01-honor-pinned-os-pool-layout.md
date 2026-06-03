# 01 — Honor template-pinned os_pool layout in the picker

Status: done

## Parent
`.scratch/picker-template-pinned-layout/PRD.md` (ADR 0029).

## What to build
Make `tools/pick.sh` + `lib/picker.sh` honor an optional layout pin in
the merged Install Template, falling back to today's prompt when
absent.

Scope:
- Pin detection in `pick.sh`: after `picker_load_template`, read
  `.mode` from the merged template. Absent → current prompt flow.
- single pin: skip the mode prompt; collect disks; validate count == 1.
- multi pin: require `.os_pool.topology`; error if absent ("multi pin
  requires os_pool.topology"). Skip the mode prompt; collect disks;
  validate via the min-disk table.
- Extend `picker_validate_layout` with a topology→min-disk table:
  mirror/stripe ≥2, raidz1 ≥3, raidz2 ≥4, none ≥2 (keep the existing
  single/mirror/raidz prompt tokens working).
- `picker_assemble_config`: add a pinned branch that writes `.mode`,
  `.os_pool.topology` (verbatim from template) and `.os_pool.disks`
  (picked); `del(.disk)` for multi, write `.disk` for single. Leave
  `storage_groups[]` / `data_pools[]` untouched.
- UX: print a notice naming the pinned mode/topology before the disk
  pick; `[e]dit` re-enters at disks only when pinned.
- Update CONTEXT.md (Pre-Install Picker, Install Template) and
  REFERENCE.md to describe pinning as shipped (drop the "planned"
  hedge); update the Diagram 1 note in `.os/ARCHITECTURE.md`.

## Acceptance criteria
- [ ] Template `mode: "multi"` + `os_pool.topology: "mirror"`, no
      disks → picker skips the mode prompt, picks ≥2 disks, writes
      `install.jsonc` with that topology + picked disks.
- [ ] Template `mode: "single"` → skips the mode prompt, requires
      exactly 1 disk.
- [ ] `mode: "multi"` without `os_pool.topology` → picker errors.
- [ ] Pinned `raidz2` with 3 disks → count error; with 4 → ok.
- [ ] No `.mode` → unchanged prompt flow (single/mirror/raidz).
- [ ] Template `os_pool.disks` present → overridden by picked disks.
- [ ] `tests/picker.bats` covers pinned skip, count validation,
      partial-pin error, and the unpinned regression.

## Notes
- `vm/arch-secure` already carries the target pin shape (ADR 0029).
- Min-disk rules mirror REFERENCE § Topology Options.
