# 03: Umbriel audit probe + `umbriel-pure` Audit Variant

**What to build:** The Feature Audit proves an Umbriel session works, and a
broken session becomes a Finding. A co-located probe, gated on the running
session being Umbriel:
- runs `umbriel config validate` on the active config
- checks IPC answers (`umbriel workspaces --json`)
- sources the shared wlroots checks

The Probe Gate SKIPs (never fails) curated/shell checks on stock. An
`umbriel-pure` Audit Variant joins the Audit Manifest.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] Probe present; manifest coverage bats pass (no probe-less program)
- [ ] `umbriel-pure` variant in the manifest
- [ ] VM Audit Run of `umbriel-pure`: probe PASSes, gated checks listed as
      SKIP with reasons, no unexplained Findings

Spec: ../PRD.md · ADR 0152, 0159
