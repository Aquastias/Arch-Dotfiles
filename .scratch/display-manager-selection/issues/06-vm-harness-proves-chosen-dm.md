# 06 — VM harness proves the chosen Display Manager

**What to build:** The VM session-verify matrix confirms the operator's chosen
greeter is the one actually enabled, not just that some session comes up. The
SDDM-autologin session prober (a test launcher, not the product) keeps launching
each session and additionally asserts the *resolved* display manager's service
is enabled, so a greetd profile still verifies the right greeter. SDDM is
installed for the probe regardless of the chosen greeter, and the existing
SDDM-launched Hyprland session coverage is retained.

**Blocked by:** 03.

**Status:** ready-for-agent

- [ ] The session prober asserts the resolved display manager's service is
      `is-enabled` on the installed guest, for both a greetd-resolved and an
      sddm-resolved profile.
- [ ] The harness installs SDDM on the guest to drive the autologin prober even
      when the resolved display manager is greetd, without changing which
      greeter the install enables.
- [ ] SDDM-launched Hyprland stays covered (the compositor comes up —
      `===HYPR-SESSION-OK===`), and Plasma coverage is unchanged.
- [ ] The matrix run is green end to end.
