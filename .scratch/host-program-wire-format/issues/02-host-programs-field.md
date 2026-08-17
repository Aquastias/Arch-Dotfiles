# 02 — Host Profile field → `host_programs`

**What to build:** A Host Profile declares its root/pacman programs under
`host_programs` (and drops an inherited one via `host_programs_exclude`) instead
of `system_programs`. The closed schema accepts the new keys and aborts on the
retired ones; the [[Layer Resolver]] merges `host_programs` as the additive key
(concat + dedupe, `host_programs_exclude` subtracts); the toggle-derived
Printing / Bluetooth / Power Host Programs inject into `host_programs` at
assembly; and the Guided Installer's menu key, host-program picker, entry-time
routing, and Save / Export all speak the new field. Every committed profile is
migrated so the repo loads clean under the closed schema. What lands on a
machine does not change.

**Blocked by:** 01 — shares the `guided.sh` / `validation.sh` consumer files, so
it lands after the kind-enum ticket to avoid colliding edits.

**Status:** ready-for-agent

- [ ] Hosts declare `host_programs` / `host_programs_exclude`; the closed schema
      accepts them and aborts on `system_programs` / `system_programs_exclude`
      naming the path (regression).
- [ ] The Layer Resolver additive-key table lists `host_programs`; additive
      merge, dedupe, and exclude-subtraction behave exactly as before.
- [ ] Toggle-derived Printing / Bluetooth / Power injection lands in
      `.host_programs` at assembly time.
- [ ] The Guided menu field key, host-program picker emit, typed-entry routing,
      and Save / Export all use `host_programs`.
- [ ] The combination-matrix registry row is renamed to `host_programs`.
- [ ] Host Core, the desktop and laptop profiles, the committed VM host
      profiles, and all bats fixtures are migrated; the config bats suite and
      `explain-packages` are green.
