# 05 — Agent doc + CLAUDE.md pointer + toolkit convention

**What to build:** the agent-facing documentation for the finished [[VM Agent
Control]] CLI, written against the **real** verbs. `docs/agents/vm-agent-control.md`
covers every verb and the hard-won gotchas — session env from
`/proc/<pid>/environ`, grim-vs-spectacle by compositor, waking the display before
a shot, self-matching `pgrep -f` false positives — plus the toolkit-test
convention: Qt checks use a KDE app (Dolphin by default), GTK checks use any GTK
app (agent's choice, `nm-connection-editor` default). A one-line pointer is added
to the repo `CLAUDE.md` agent-skills/docs section so a cold agent discovers it.

**Blocked by:** 02, 03, 04 (the doc describes the verbs those tickets deliver).

**Status:** ready-for-agent

- [ ] `docs/agents/vm-agent-control.md` documents all verbs (`session`, `shot`,
      `exec`, `launch`, `logout`, `reboot`, `idle`, `lock`, `unlock`, `ssh`,
      `ready`) and the gotchas above.
- [ ] The doc states the Qt=KDE-app (Dolphin) / GTK=any (nm-connection-editor)
      convention.
- [ ] `CLAUDE.md` gains a one-line pointer to the doc under the agent
      skills/docs section.
- [ ] The doc is sufficient to drive a cold agent through a full session-switch +
      screenshot without rediscovering the plumbing.
