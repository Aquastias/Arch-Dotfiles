# Arch Wiki grounding

Package and config decisions in this repo are grounded in the **Arch Wiki**, not
in memory. When you add a package, author or edit a program, or wire up a
service/group/kernel-param, read the relevant Arch Wiki page first and make the
repo match it.

**Fetch it, don't recall it.** Open the actual page (`WebFetch` on
`wiki.archlinux.org`, or `WebSearch` to find it) — LLM memory drifts on package
names, service units, and whether a group is still required. The `gamemode`
example is the cautionary tale: recalling "add the user to the `gamemode` group"
would have been wrong — the wiki/polkit path is current.

## Two scopes

- **Program specs** (`.os/programs/<name>/config.jsonc` + `install.sh`). The
  authoring contract is `.os/programs/PROGRAM_SPEC.md` — feed it the wiki page
  and it dictates package sourcing, service declaration, groups, and kernel
  params. Every package and every config value must trace to the wiki page.

- **Bare package additions** (`packages.repo` / `packages.aur` in Host Core or a
  host profile). A package line is not always the whole story — the wiki's
  Installation / Configuration sections say whether the thing also needs a
  service enabled, a group, a polkit/limits drop-in, or a kernel param. If it
  does, that is a **program spec**, not a bare package line. If a bare package
  genuinely needs nothing more (wiki confirms it is package-only / D-Bus- or
  socket-activated), a `packages.*` entry is correct — say so, citing the wiki.

## Rules (both scopes)

- Repo packages first; AUR **only** if the wiki calls for it (AUR needs
  `kind: "user"` + `paru`).
- Config values match the wiki recommendation exactly — no invented keys.
- Never `systemctl start`; ship services via `system_services` / `user_services`
  (or `systemctl enable` only for units the script itself writes).
- When the wiki says a package needs more than installing, either wire it up (as
  a program spec) or, if out of scope, surface the gap rather than leaving a
  bare package silently under-configured.
