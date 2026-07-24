# `install-pkglist.sh` — auto-detect the AUR helper

Status: done

## Parent

`.scratch/aur-helper-ladder/PRD.md` — Resilient AUR-helper bootstrap ladder
(ADR 0052).

## What to build

The standalone post-install tool `install-pkglist.sh` keeps working on a system
where the ladder landed `yay` instead of `paru`. It runs on a booted system,
outside the Runner's env-injection seam, so it resolves the helper itself: prefer
`paru`, else `yay`, and die with a clear message if neither is installed. It then
installs from the pkglist with whichever helper it found.

Reuse `_profiles_detect_helper` if the tool can source it; otherwise inline an
equivalent `command -v paru || command -v yay` check so there is a single
behavioural definition.

## Acceptance criteria

- [ ] `install-pkglist.sh` selects `paru` when present, else `yay`.
- [ ] It dies with a clear "no AUR helper found" message when neither exists
      (replacing today's paru-only "paru not found" check).
- [ ] It runs `<helper> -S --needed - < list` for both the repo and AUR lists
      with the detected helper.
- [ ] A focused bats/harness test stubs PATH and asserts helper selection plus
      the die-if-neither path.

## Blocked by

- Ticket 01 (Ladder foundations) — shares `_profiles_detect_helper`.
