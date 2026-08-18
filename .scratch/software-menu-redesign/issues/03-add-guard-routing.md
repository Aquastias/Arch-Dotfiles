# 03 — `＋Add` guard routing (pure)

**What to build:** Replace the old silent kind-routing of a typed package entry
with an explicit, visible guard. Given a name (and the slot it was typed into),
route it: a [[Menu-Owned Program]] informs the operator it is managed by its
control and makes **no** state change; a free-standing [[User Program]] is added
to the Primary User's `programs` (`users[0]`) with a visible message; anything
else is appended to `packages.<slot>.extra`. This preserves the config-load
exclusivity safety the old routing gave (a Program name never lands in
`packages.*`) while making every reclassification explicit. The old
emit-path/entry-path promotion rule is removed.

Routing decision, trimmed from the validated prototype
(`.scratch/software-menu-redesign/prototype-tui.html`):

```
route(name, slot):
  if name is Menu-Owned      -> inform "managed by <Control>"; no state change
  else if kind(name) == user -> add to users[0].programs; inform "→ Users"
  else                       -> append to packages.<slot>.extra
```

**Blocked by:** 01 — needs `menu_owned_programs` and the owner→control label to
name the managing control.

**Status:** ready-for-agent

- [ ] Routing a Menu-Owned name (e.g. `grub`, `clamav`) leaves Config State
      unchanged and reports the owning control.
- [ ] Routing a free-standing user program name (e.g. `docker`) appends it to
      `users[0].programs` and reports the redirect.
- [ ] Routing an ordinary name (e.g. `ripgrep`) appends it to
      `packages.<slot>.extra` for both `repo` and `aur` slots.
- [ ] With no users declared, a user-program name falls back sanely rather than
      being silently dropped.
- [ ] No path lets a Program name reach `packages.*` (config-load exclusivity
      stays satisfiable).
- [ ] Covered in `guided-packages.bats`, following the free-text add and
      exclude/provenance prior art.
