# 01: Install summary joins Security & Backup Extras with alternating separators

**What to build:** The install plan's "Security & Backup Extras" line lists
the selected programs separated by `, `. Today it prints
`firewalld,clamav rkhunter,apparmor zfs-auto-snapshot,borg`: the old
`paste -sd ', '` cycled its two delimiter characters instead of using the
pair. Found during the readability pilot (ticket 05 of
`.scratch/human-readable-installer/`), which kept the output byte-identical.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Extras print as `firewalld, clamav, rkhunter, …` in
      `lifecycle_print_summary`
- [x] A test pins the joined line for three or more extras

## Same pattern elsewhere

`lib/guided/shell.sh` `_guided_shell_save` joins the Save-warn user list the
same way (was `paste -sd', '`, kept byte-identical in the readability
refactor): `a,b c,d` instead of `a, b, c, d`.

## Comments

The extras line was fixed during the ADR 0167 migration; both sites now use
the Commons `join_list` (`a, b, c`), the Save-warn included.
