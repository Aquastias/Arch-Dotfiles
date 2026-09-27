# 02: Curated `settings.json`

**What to build:** The seeded/stowed `settings.json` carries the operator's
decided configuration rather than an ad-hoc snapshot. Apply every settings
decision from ADR 0133 to the tracked file. A user on a fresh box gets a Claude
Code that opens in auto mode, never adds Claude attribution, runs the sandbox
with libvirt reachable, and uses the operator's model/retention/notification
choices.

**Blocked by:** 01 (the tracked file must exist to edit).

**Status:** done

- [x] Attribution off: `attribution.commit` = `""`, `attribution.pr` = `""`,
      `attribution.sessionUrl: false`
- [x] Launch in auto mode: `permissions.defaultMode: "auto"`,
      `skipAutoPermissionPrompt: true`,
      `disableBypassPermissionsMode: "disable"`
- [x] Sandbox: `network.allowUnixSockets` includes the libvirt sockets
      (`/run/libvirt/libvirt-sock`, `…-sock-ro`), `failIfUnavailable: true`;
      existing `filesystem` block retained
- [x] Model `claude-opus-4-8`; `fallbackModel: ["claude-sonnet-5"]`;
      `promptCacheTtl: 3600`
- [x] `cleanupPeriodDays: 30`, `feedbackSurveyRate: 0`,
      `preferredNotifChannel: "desktop"`, `autoUpdatesChannel: "stable"`,
      `emojiCompletionEnabled: false`
- [x] `voice.{enabled,mode}` and `voiceEnabled` seeded verbatim (unchanged)
- [x] `settings.local.json` and `.credentials.json` untouched

## Comments

- 2026-09-27 doc sync: shipped in 6521bc3, 2bb7784, 6e78829, 2711118, 8d7adf8,
  0529dd6, 4039310, 88a7516, 1f74b30 (ADR 0133).
