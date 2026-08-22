# 05 — Host Core Kate language servers

**What to build:** The operator's real machines get editor code
intelligence for their languages. Host Core declares the language
servers so desktop and laptop install them while VM fixtures stay lean
(they already opt out via `packages.inherit: false`). Repo servers go in
`packages.repo`: `bash-language-server`, `yaml-language-server`,
`typescript-language-server` (js+ts), `rust-analyzer`, `gopls`, `zls`,
`clang` (clangd ships inside it). The one server with no `extra`
package, `vscode-langservers-extracted` (json/css/html), goes in
`packages.aur` and installs via the Primary User's paru pass. The Nix
server is skipped for now. These are general dev tooling, not DE-tied, so
they live in Host Core, never the KDE adapter — the adapter's repo-only
guarantee is untouched (ADR 0088).

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Host Core `packages.repo` gains the seven repo language servers
- [ ] Host Core `packages.aur` gains `vscode-langservers-extracted`
- [ ] No Nix server (`nil`/`nixd`) is declared
- [ ] The Package Resolver / real-profile regression reports the servers
      with the correct repo vs aur layer
- [ ] VM fixtures do not receive the servers (existing `inherit: false`)
