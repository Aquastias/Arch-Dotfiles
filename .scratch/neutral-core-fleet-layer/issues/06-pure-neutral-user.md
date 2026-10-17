# 06: `*-pure` profiles use a neutral user

**What to build:** a stock install carries no personal userland. `kde-pure`,
`niri-pure` and `hyprland-pure` stop declaring `aquastias` and use a neutral
user (reuse `server` or add a neutral desktop user — implementer's choice,
stated in the profile headers). See PRD, [[ADR 0112]], [[ADR 0157]].

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The three pure profiles resolve with no User Program of `aquastias`
- [ ] Each still validates and installs a working login for its desktop
- [ ] CONTEXT.md Pure (Stock) Profiles entry updated
