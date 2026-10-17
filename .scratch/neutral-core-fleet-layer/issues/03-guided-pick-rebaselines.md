# 03: Guided profile pick re-baselines

**What to build:** picking a Host Profile in the Guided Installer installs
exactly what `install.sh --profile <name>` installs. Today the pick overlays
the resolved profile onto the Host Core baseline and any earlier pick, so
`minimal` / `*-pure` still carry the 105 Host Core packages and the secure
extras. One Profiles-module function re-baselines the session — full session
reset (as `＋ New host`), then the resolved profile becomes the baseline with no
● marks — and both the interactive Profiles screen and the headless replay
call it. See PRD and [[ADR 0157]].

**Blocked by:** None (can start immediately)

**Status:** done

- [x] For every committed Host Profile, the headless replay's Effective Config
      after a pick equals the `--profile` Effective Config (devices and
      secrets masked)
- [x] Picking `desktop` then `minimal` equals a fresh `minimal` pick
- [x] Picking `minimal` yields no Host Core packages and no Security & Backup
      Extras
- [x] The interactive controller and the replay share the one function (no
      duplicated resolve-then-seed)
- [x] Picked values render with no ● override marks
- [x] guided-profiles / guided-seed bats updated where they asserted overlay
      semantics; suite green
