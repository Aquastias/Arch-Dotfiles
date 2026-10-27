# 05: Org and REST

**What to build:** Doom org and nvim's orgmode work on the same notes: same
org directory, agenda files and default refile file as nvim (ADR 0160). A
REST client on `SPC R s` (send) and `SPC R c` (copy as curl) via
`restclient`, recorded as a **loose match** — its format is close to, not
identical with, rest.nvim's `.http`.

**Blocked by:** 01 (Tracer).

**Status:** done

- [x] `init.el` enables org; `config.el` sets nvim's org paths
- [x] `packages.el` adds restclient; `SPC R s`/`SPC R c` bound
- [x] Static bats: org paths match nvim's orgmode config; REST binds present
- [x] VM: agenda lists a note from the shared org dir; a request in a
      sample file sends; noted in Comments
- [x] `.http` format differences found are recorded for the ADR

## Comments

- restclient comes from Doom's `:lang rest` module (pinned there), not
  `packages.el`; that module maps `.http` files to restclient-mode.
- nvim's agenda glob `~/orgfiles/**/*` is recursive; Emacs agenda dirs are
  not, so an `org-agenda` advice refreshes the recursive file list first.

- VM (arch-kde): agenda lists a TODO from ~/orgfiles/sub (recursive);
  .http → restclient-mode, GET https://archlinux.org/ → HTTP/1.1 200. No
  format differences hit in the sample; restclient stays a loose match.
