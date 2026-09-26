# 08: Populate initial pins

**What to build:** the operator runs `aur-vet seed`, reviews every declared
AUR package and dependency, and commits the populated repo pin file, so
unattended installs can pass. Includes accepting or allowlisting any
suspicious findings on known-good packages.

**Blocked by:** 03, 07.

**Status:** ready-for-human

- [ ] Every declared AUR base and AUR dependency has a Vetted Commit.
- [ ] A VM test install (desktop profile) completes with vetting active.
- [ ] The pin file is committed.
