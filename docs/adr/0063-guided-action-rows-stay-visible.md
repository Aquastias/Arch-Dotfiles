# Guided action rows stay visible as list rows

ADR 0047's chrome split moved list-embedded actions (Back / Add / Remove /
Create) onto the `^A`/`^X`/`Esc` keybindings so rich-chrome lists "held only
data". On modern fzf (≥ 0.62, where rich chrome is always on) this made every
mutation affordance invisible — notably `+ Create user`, which an operator
could reach only by knowing the undocumented `^A` shortcut. Reverse that
portion of 0047: every action row (`+ Create/Add …`, `✗ remove …`, `← Back`)
renders as a visible list row again in rich chrome, exactly as legacy chrome
already did; the `^A`/`^X`/`Esc` keybindings stay as accelerators. `_ctl_action_row`
becomes an unconditional emit rather than a rich-chrome gate.

The trade-off is a slightly busier list (a `← Back` row on every screen,
duplicating `Esc`) against discoverable create/add/remove actions; discoverability
wins, because a hidden `+ Create user` was the concrete failure that motivated
this. The disk-binding, Free Set, and freeform-layout decisions of ADR 0047 are
untouched — only its actions-on-keybindings sub-decision is amended.

## Status

accepted — amends ADR 0047 (rich-chrome action-row placement only)
