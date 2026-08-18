# 04 — `repo ＋Add` fzf pacman browser

**What to build:** On the Software → `repo` screen, `＋Add` opens an
archinstall-style package browser built on the installer's own fzf surface:
`pacman -Slq | fzf --multi --preview 'pacman -Si {}'` — a filterable list of
every official-repo package with an info preview pane and multi-select. On
confirm, each picked name flows through the ticket-03 guard (Menu-Owned →
informed, free user program → Users, else → `packages.repo.extra`). The `aur`
`＋Add` stays the current free-text prompt (AUR is not in the sync DB and paru is
not bootstrapped at menu time). From the operator's view: adding repo packages
feels like archinstall's selector, and every pick is routed visibly.

**Blocked by:** 03 — the browser feeds picked names into the guard.

**Status:** ready-for-agent

- [ ] `repo → ＋Add` launches the fzf browser sourced from `pacman -Slq`, with a
      `pacman -Si {}` preview and multi-select.
- [ ] Confirmed picks are each routed through the ticket-03 guard.
- [ ] `aur → ＋Add` still uses the free-text prompt (unchanged).
- [ ] An unsynced/empty pacman DB fails understandably rather than silently (the
      `pacman -Sy` gotcha, upstream archinstall issue #3307).
- [ ] The interactive browser is not unit-tested (tty + live pacman DB, out of
      scope per spec); verify manually. Any pure helper it factors out (e.g. the
      routing over a confirmed pick list) is covered by ticket 03's tests.
