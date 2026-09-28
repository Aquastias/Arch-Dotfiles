# 08: Close-out — full suite, docs, unattended VM install

**What to build:** On-the-fly [[AUR Vetting]] proven end to end: the full
suite passes, ADR 0143/0149 and the glossary match what shipped, and a VM
install from the local repo completes unattended with the current AUR set —
including the `claude` program, whose `ccusage` change aborted the VSCodium
VM run.

**Blocked by:** 01, 02, 03, 04, 05, 06, 07.

**Status:** ready-for-agent

- [ ] Full bats + shellcheck + no-python green (pre-existing failures noted)
- [ ] VM `arch-combined` from the local repo: unattended install completes,
      no `programs_exclude` workaround; any prompt-worthy finding recorded
- [ ] ADR 0149 status → implemented; ADR 0143 / CONTEXT.md consistent
- [ ] SPEC.md status → done
