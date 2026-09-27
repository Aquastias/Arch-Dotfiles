# 02 — Promote ccache to a Host Program

**What to build:** After install, `ccache` is actually enabled — `/etc/makepkg.conf`
has the `ccache` `BUILDENV` flag on, so repeated `makepkg`/AUR rebuilds are
cached. Promote `ccache` from a bare `packages.repo` entry into a `kind: host`
Program under a new `dev` category (single home, ADR 0089): its `install.sh`
installs the package and enables ccache in `makepkg.conf`. It runs
unconditionally on every real host and never appears in a Guided picker. Grounded
on the Arch Wiki ccache page per `docs/agents/arch-wiki.md` and authored to
`PROGRAM_SPEC.md`.

**Blocked by:** 01 — Core-Owned Program filter (needs `core_owned_programs`).

**Status:** done

- [x] `programs/dev/ccache/` exists with `config.jsonc` (`kind: host`) and
      `install.sh`, both matching `PROGRAM_SPEC.md`.
- [x] `install.sh` installs `ccache` via `pacman --needed` and flips the
      `BUILDENV` `!ccache`→`ccache` in `/etc/makepkg.conf` idempotently
      (append-after-delete; converges whether the flag starts on or off).
- [x] `ccache` is removed from Host Core `packages.repo` (`dev` group) and added
      to Host Core `host_programs`.
- [x] `ccache` is added to `core_owned_programs`, so it is filtered from both
      pickers and the host-programs row stays absent.
- [x] `ccache` is added to `host_programs_exclude` in `arch-kde`, `arch-secure`,
      and `arch-data` VM fixtures.
- [x] Config-resolution tests assert `ccache` is absent from resolved
      `packages.repo` and present in resolved `host_programs` on desktop/laptop,
      and absent from the VM fixtures' resolved `host_programs`.
- [x] `core_owned_programs` test asserts it contains `ccache`.
- [x] `tests/audit.sh` passes (folder is `kind: host`, files present, reference
      resolves); full bats suite green.

## Comments

- 2026-09-27 audit: ce126da, 484aa2b. Later: core_owned_programs removed
  (c1d30d0); VM fixtures drop core programs via packages.inherit:false
  (87691a9).
