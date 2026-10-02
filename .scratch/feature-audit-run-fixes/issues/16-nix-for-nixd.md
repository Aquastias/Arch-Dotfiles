# 16: nix alongside nixd

**What to build:** Host Core installs nix with nixd so the Nix LSP's
evaluator does not abort. Arch Wiki-grounded. Fixes nixd-attrset-eval
coredumps (F550-F552 etc.).

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base)

## Comments

nix was already installed; root cause /nix/store missing (worker aborts). New
nix host program: nix-daemon + tmpfiles store (43822af).
