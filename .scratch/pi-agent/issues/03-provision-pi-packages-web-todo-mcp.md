# 03: Provision pi packages (web / todo / MCP)

**What to build:** Pi gains the capabilities its minimal core omits — web
search/fetch, todo tracking, and MCP — so skills like `research` function and
the agent matches Claude Code's staples. Web search is private-first and never
hard-fails.

Scope: add three packages to `settings.json` `packages` — `nicobailon/
pi-web-access` pointed at the host's SearXNG (`http://127.0.0.1:8080`, installed
for every real user via User Core) with a keyless DuckDuckGo fallback;
`@juicesharp/rpiv-todo`; and `pi-mcp-adapter`. Ship a stow-ready starter
`~/.pi/agent/mcp.json` (Claude-style `mcpServers`; secret values via `${VAR}`
interpolation; servers lazy). Anchored by ADR 0127.

**Blocked by:** 01 (needs the installed pi + settings.json).

**Status:** ready-for-agent

- [ ] `settings.json` `packages` lists the web, todo, and MCP packages.
- [ ] The web tool is configured to query SearXNG at `127.0.0.1:8080` with a
      DuckDuckGo fallback.
- [ ] A starter `mcp.json` (valid `mcpServers` shape, `${VAR}` for secrets) is
      seeded and stow-ready; no secret value is committed.
- [ ] `pi-agent.bats` asserts the three packages in settings and the `mcp.json`
      shape.
- [ ] On the `arch-combined` VM, the three packages load and a web search returns
      results (SearXNG path, with fallback exercised when the container is down).
