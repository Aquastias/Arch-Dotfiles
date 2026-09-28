# 08: Close-out — full suite, docs, unattended VM install

**What to build:** On-the-fly [[AUR Vetting]] proven end to end: the full
suite passes, ADR 0143/0149 and the glossary match what shipped, and a VM
install from the local repo completes unattended with the current AUR set —
including the `claude` program, whose `ccusage` change aborted the VSCodium
VM run.

**Blocked by:** 01, 02, 03, 04, 05, 06, 07.

**Status:** done

- [x] Full bats + shellcheck + no-python green (pre-existing failures noted)
- [x] VM `arch-combined` from the local repo: unattended install completes,
      no `programs_exclude` workaround; any prompt-worthy finding recorded
- [x] ADR 0149 status → implemented; ADR 0143 / CONTEXT.md consistent
- [x] SPEC.md status → done

## Comments

- VM run 1 (d189c9b^): aborted at `qt-sudo` (an `octopi` AUR dep) —
  `sudo-in-pkg` matched the word "sudo" in its plain `pkgdesc`. Fixed
  (plain pkgdesc skipped; `sudo` only in command position); a live check of
  the full AUR closure (28 bases, deps via RPC) then passed.
- VM run 2 (d189c9b, local repo via REPO_URL, no `programs_exclude`):
  unattended install completed, `claude` program included. On the booted
  system: `/etc/aur-vet` holds only `allow.tsv`, paru `[bin]` carries the
  hook, `aur-vet doctor` clean, 30 AUR packages installed (`claude-code`,
  `ccusage`, `qt-sudo`, `vscodium-bin` among them).
- Full bats: only the 4 pre-existing failures (initcpio x3, claude-agent
  settings drift). shellcheck and no-python clean.
