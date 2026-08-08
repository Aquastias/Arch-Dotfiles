# 01 — Re-cut Configuration Categories 8 → 12 (Seam 1)

**What to build:** The Guided Installer's top-level menu shows twelve
single-purpose Configuration Categories in archinstall reading order, each field
living under its new, archinstall-named home — with zero change to any field path
or the install back-end. This is a pure Menu-model data edit: relabel each field's
`section` and rewrite the category table.

Final categories, in order, with every current field's new home:

| # | Category | Fields | Moved from |
|---|----------|--------|------------|
| 1 | Locales | locale, keymap | Host |
| 2 | Mirrors & Repositories | mirror countries, multilib | Options |
| 3 | Disks | filesystem, encryption, impermanence, esp size, swap, pools | — |
| 4 | Bootloader | bootloader | Options |
| 5 | Kernels | kernel | Options |
| 6 | System | hostname, timezone | Host |
| 7 | Users | primary user, extra accounts | — |
| 8 | Environment | desktop, display manager, gpu | — |
| 9 | Packages | repo, aur, derived, system programs, extra | — |
| 10 | Security | firewall, antivirus, rootkit, apparmor, sysctl | Options (sysctl) |
| 11 | Backup | snapshots, borg | — |
| 12 | Advanced | ssh, age key url | Options |

Reflector is untouched — `options.mirror_countries` keeps its path and its
`reflector --country … --latest 10 --sort rate` consumer; only its `section`
label moves to *Mirrors & Repositories*. Category-level summaries update to the
new groupings. Respect ADR 0071.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The top-level category list renders the twelve categories above, in this
      order.
- [ ] Every current field surfaces under its new `section`; no field's dotted
      path changes (`options.*` / `system.*` unchanged).
- [ ] `sysctl` appears under Security; `ssh` + `age key url` are the only fields
      under Advanced; the old "Options" and "Host" categories are gone.
- [ ] A category's `●` still folds the override flags of its member fields
      (`menu_categories` / `menu_rows` JSON contract preserved).
- [ ] `guided-menu.bats` and `menu-enum.bats` are updated to assert the twelve
      categories, their order, and each field's new section — and pass.
- [ ] A `--guided` replay test proves an answer file written against the old
      section names still resolves every field (paths unchanged).
