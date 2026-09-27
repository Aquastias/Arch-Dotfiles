# 07 — Primary User identity: avatar + display name

**What to build:** The Primary User shows the operator's chosen avatar and
display name on a fresh install — the lightbulb image in the greeter/session and
the name "Alex" — without touching any other account. (ADR 0121)

**Blocked by:** None — can start immediately.

**Status:** done

- [x] The vendored 256×256 lightbulb PNG is seeded to `/etc/skel/.face` and
      written as the Primary User's AccountsService record + icon at user
      creation.
- [x] The Primary User's GECOS full name is set via `useradd -c`, defaulting to
      `"Alex"`, overridable by an explicit full-name value.
- [x] Only the Primary User is affected — no other account gets the avatar/name.
- [x] `chroot/chroot-create-user.bats` asserts the `useradd`/`usermod`
      invocation carries `-c "Alex"` for the Primary User and that an explicit
      full name overrides the default.

## Comments

- 2026-09-27 doc sync: shipped in 8a32898, 54ecfba, 41a2188, 378db0b, a96edbc,
  e79ca17, 4352be4, dfc347d, 8f3795b, badf9e0, cd8f5a0, 840dfea, f598ff0 (ADR
  0118-0121).
