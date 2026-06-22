# Guided Installer renders through one persistent fzf, not one fzf per pick

The Guided Installer's interactive shell is rebuilt so a **single long-lived
fzf process owns the loop** for the whole session — moving between the category
list, a category's fields, and value edits happens via fzf `reload`/`transform`
binds that call a bash *controller*, instead of spawning a fresh fzf per
interaction. This removes the inter-process flash back to the bare terminal and
keeps the toolbar (`^Z`/`^Y`/`^R` + the terminal-action rows) present and live
at every depth. fzf is retained (no new dependency, per ADR 0039); what changes
is the control model — fzf calls bash, not bash calls fzf — not the renderer.

## Considered Options

- **Persistent single-fzf controller** — chosen. Seamless, bash-only, keeps the
  pure cores and the disk-picker preview pane. The impure shell flips
  inside-out and the interactive override map moves from a shell var to a tmpfs
  state file so fzf bind-children can read and mutate it.
- **Incremental fix** (header on the subloop + `--no-clear`) — rejected as the
  end state: fixes the toolbar but never removes the flash (N processes remain).
  Adopted only as a throwaway stopgap until the rewrite lands.
- **Compiled full-screen TUI** (ratatui/Rust or bubbletea/Go) — rejected: a
  compiled binary in the audit repo (against ADR 0036's committed-artifact
  spine), a language boundary forcing the pure cores to be subprocess-bridged or
  duplicated, and a rewritten replay/test seam — all for polish whose only true
  fzf deficit (masked password entry) is already handled post-menu. Of the two,
  bubbletea would be preferred over ratatui (static binary, `huh` form fit), but
  the structural costs are identical and disqualifying.

## Consequences

- Free-text fields are typed into fzf's own query line and captured via a
  `transform` bind (`{q}` → state file), so editing never leaves the window.
- Secrets and the typed consent gates (`ACCEPT`/`INSTALL`) are collected
  **after** the menu exits, in the existing terminal stage, via `prompt_secret`
  (hidden, read-twice, confirmed) — the in-menu surface stays fully seamless,
  passwords never touch the query line or the state file, and today's plaintext
  password echo (`guided_prompt` for `root_password`/`new_user_password`) is
  fixed.
- The headless replay seam (`--guided <answers>`, keyed) and its bats stay
  frozen (redesign user story 27): interactive and headless now share the pure
  cores plus extracted pure setters, **not** control flow. The new controller is
  event-driven and gets its own bats; the live fzf draw stays smoke-only.
- The persistent menu is **config-only**: all disk resolution (single *and*
  multi) happens in the post-menu terminal stage, reusing the existing one-shot
  `guided_pick_disk`/`guided_pick_disks` with their `--preview` panes intact.
  fzf's `--multi` is launch-only (no runtime toggle), so a single-select
  persistent instance cannot host the multi-disk pick — hence disks resolve at
  the commit step, not mid-config, and the menu needs no preview plumbing.
