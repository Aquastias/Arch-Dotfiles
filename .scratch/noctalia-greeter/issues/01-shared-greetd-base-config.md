# 01: Shared greetd base config (prefactor)

**What to build:** The greetd Display Manager Adapter builds its greetd config
from a shared helper that owns the greeter-agnostic parts — VT 2, the
`greeter` user, and the drop-in that conflicts greetd with the tty2 getty —
taking only the greeter command from its caller. greetd + tuigreet behaves
exactly as today; this makes adding a second greetd greeter a one-command
change ([ADR 0158]).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] The greetd/tuigreet adapter writes byte-identical config and drop-in to
      today's, via the shared helper.
- [x] The helper lives in the chroot world (`lib/chroot`), staged for extras,
      reused not duplicated (`docs/agents/shell-commons.md`).
- [x] Existing greetd adapter tests stay green; the noctalia-greeter adapter
      test (03) covers a second caller.
