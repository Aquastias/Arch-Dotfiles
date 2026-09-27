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

- 2026-09-27 audit: 2bb7784, a0a86fe. Later amended by ADR 0142 (17aee35): model
  now claude-opus-5-5, unused features disabled.
