# 01 — Display Manager as a resolved config axis

**What to build:** The operator can author `environment.display_manager`
(`auto` | `greetd` | `sddm`, default `auto`) in a Host Profile, and the
installer resolves it at config load into a concrete greeter carried into the
chroot — `auto` becomes `greetd` when Hyprland is in the resolved desktop set,
`sddm` otherwise, and `none` when no desktop is selected; an explicit `greetd`
or `sddm` passes through unchanged. Nothing consumes the resolved value at
dispatch yet, so the Desktop Environment Adapters keep enabling the display
manager exactly as today and every existing profile installs identically. This
ticket lays the data spine and its guards.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `environment.display_manager` is accepted by the closed Host Profile
      schema; an unknown value aborts at config load with its schema path.
- [ ] Config-load resolution sets a concrete display manager: `auto` →
      `greetd` if `hyprland` is in the resolved desktop set, else `sddm`;
      `none` when the desktop set is empty; explicit `greetd`/`sddm` unchanged.
- [ ] A concrete display manager with an empty desktop set aborts with an
      actionable message; `auto` with an empty desktop set resolves to `none`.
- [ ] The resolved concrete value is threaded into Install State as a new
      scalar field (modeled on the resolved GPU field) and kept in the
      host-write / chroot-load schema list.
- [ ] The Layer Resolver treats `environment.display_manager` as a replace key
      (no new merge classification).
- [ ] Existing behavior is unchanged: the VM environment matrix stays green and
      the Desktop Environment Adapters still enable their display managers.
- [ ] Resolution and validation are covered by the environment-resolution and
      environment-validation bats (prior art: the GPU `auto` cases).
