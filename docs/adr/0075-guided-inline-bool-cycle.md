# Guided bare-bool leaves flip in place instead of drilling

A Guided-Installer leaf whose entire value set is `true`/`false` (a **Cycle
Field**) now flips on the category screen — Enter advances to the other value
and stays put (`echo refresh`) — instead of drilling into the values submenu to
pick from a two-row `true`/`false` list. This generalizes the pre-existing
Manual-Partitioning in-place flip to every bare bool. A field is a Cycle Field
**structurally**, detected by its option set being exactly `{true, false}`
(`_ctl_is_cycle_field`), and the flip reuses the strict-delta apply
(`_ctl_apply_enum` + `_ctl_normalise_default`), so it inherits override-clearing
and the Manual-Partitioning lock guard unchanged.

## Considered options

- **Enumerate a `cycle` field kind** listing the eleven bool paths (as `text`
  and the multi-select `toggle` kind are listed) — rejected: the list drifts
  the moment someone adds a bool. Structural detection is self-maintaining.
- **Name it `toggle`** — rejected: `toggle` already means the multi-select
  (TAB-many) leaf kind in this installer. Reusing it would collide; `cycle`
  reuses the established `_ctl_cycle_next` / pool-editor verb instead.
- **Include every bool, incl. editor-backed ones** — rejected: `encryption`
  and `impermanence` are `▸` editor rows carrying more than a bool (passphrase,
  persist paths); flipping them in place would bypass their editors. Scope is
  **bare bools only** — the five Pacman flags, three Security and two Backup
  bools, and Advanced→SSH.

## Consequences

- No reverse key: for a two-value cycle Enter alone flips both ways.
- A Manual-Partitioning-locked bool is a **silent no-op** (the apply guard
  already returns unchanged); the shown-but-locked detail conveys the state.
- The category detail pane lists both values with the current one marked, so the
  choice stays discoverable without the submenu; the header hint reads
  `Enter edit / cycle`.
