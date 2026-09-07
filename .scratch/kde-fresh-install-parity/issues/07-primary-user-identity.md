# 07 — Primary User identity: avatar + display name

**What to build:** The Primary User shows the operator's chosen avatar and
display name on a fresh install — the lightbulb image in the greeter/session and
the name "Alex" — without touching any other account. (ADR 0121)

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The vendored 256×256 lightbulb PNG is seeded to `/etc/skel/.face` and
      written as the Primary User's AccountsService record + icon at user
      creation.
- [ ] The Primary User's GECOS full name is set via `useradd -c`, defaulting to
      `"Alex"`, overridable by an explicit full-name value.
- [ ] Only the Primary User is affected — no other account gets the avatar/name.
- [ ] `chroot/chroot-create-user.bats` asserts the `useradd`/`usermod`
      invocation carries `-c "Alex"` for the Primary User and that an explicit
      full name overrides the default.
