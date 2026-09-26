# 08: Populate initial pins

**What to build:** the operator runs `aur-vet seed`, reviews every declared
AUR package and dependency, and commits the populated repo pin file, so
unattended installs can pass. Includes accepting or allowlisting any
suspicious findings on known-good packages.

**Blocked by:** 03, 07.

**Status:** done

- [x] Every declared AUR base and AUR dependency has a Vetted Commit.
- [x] A VM test install (desktop profile) completes with vetting active.
- [x] The pin file is committed.

## Comments

Seeded by the operator (30 declared bases) plus the AUR Helper ladder
(paru, paru-bin, yay-bin). VM run `vm.sh --testing --profile env/kde`
(2026-09-26, local repo served over HTTP) passed: every rung, paru-hook and
User Program AUR build vetted PASS against its pin; installer exit 0;
first-boot `aur-vet audit: clean`, AUR audit OK, boot OK.
