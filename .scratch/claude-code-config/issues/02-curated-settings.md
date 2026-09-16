# 02: Curated `settings.json`

**What to build:** The seeded/stowed `settings.json` carries the operator's
decided configuration rather than an ad-hoc snapshot. Apply every settings
decision from ADR 0133 to the tracked file. A user on a fresh box gets a Claude
Code that opens in auto mode, never adds Claude attribution, runs the sandbox
with libvirt reachable, and uses the operator's model/retention/notification
choices.

**Blocked by:** 01 (the tracked file must exist to edit).

**Status:** ready-for-agent

- [ ] Attribution off: `attribution.commit` = `""`, `attribution.pr` = `""`,
      `attribution.sessionUrl: false`
- [ ] Launch in auto mode: `permissions.defaultMode: "auto"`,
      `skipAutoPermissionPrompt: true`, `disableBypassPermissionsMode: true`
- [ ] Sandbox: `network.allowUnixSockets` includes the libvirt sockets
      (`/run/libvirt/libvirt-sock`, `…-sock-ro`), `failIfUnavailable: true`;
      existing `filesystem` block retained
- [ ] Model `claude-opus-4-8`; `fallbackModel: ["claude-sonnet-5"]`;
      `promptCacheTtl: 3600`
- [ ] `cleanupPeriodDays: 30`, `feedbackSurveyRate: 0`,
      `preferredNotifChannel: "desktop"`, `autoUpdatesChannel: "stable"`,
      `emojiCompletionEnabled: false`
- [ ] `voice.{enabled,mode}` and `voiceEnabled` seeded verbatim (unchanged)
- [ ] `settings.local.json` and `.credentials.json` untouched
