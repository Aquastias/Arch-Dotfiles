# 04: Prefactor — parity check exempts laptop-only hardware Host Programs

**What to build:** the Fleet Golden desktop/laptop parity check compares the
shared software image only, excluding Host Programs that are laptop-only
hardware support. No behaviour change yet; ticket 05 is the first user.
Parent: PRD (ADR 0161, ADR 0114).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] The exemption is one named list, empty or holding only
      `lenovolegionlinux`, with an ADR 0161 anchor.
- [x] The parity test still fails on any other desktop/laptop difference
      (shown by a temporary local check, not a committed fixture).
- [x] Fleet Golden suite green, fixtures untouched.
