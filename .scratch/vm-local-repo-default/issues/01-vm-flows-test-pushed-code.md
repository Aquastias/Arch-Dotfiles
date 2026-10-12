# 01: VM flows silently install the pushed GitHub repo, not local work

**What to build:** `vm/lib/core.sh` defaults `REPO_URL` to the GitHub repo,
so `vm.sh` (test, guided, persistent flows) and `matrix.sh run` install
whatever is pushed to `origin/main` — not the local commits under test. On
2026-10-11/12 three "green" readability VM checks (matrix zfs-single-plain,
guided single/guided, persistent arch-combined) passed on the old pushed
code while local HEAD had two install-breaking regressions; only the Feature
Audit (which stages a bare clone of local HEAD and serves it over the
libvirt gateway) caught them.

Make local verification the easy path: e.g. a `--local` flag (or
`REPO_URL=local`) that bare-clones HEAD into the flow's CACHE_DIR, runs
`update-server-info`, and points REPO_URL at
`http://<gateway>:<HTTP_PORT>/<clone>.git` — what
`feature_audit_stage_repo` already does. Warn on uncommitted changes (the
guest clones HEAD). Consider printing the resolved REPO_URL + commit at the
start of every run so a GitHub-sourced run is never mistaken for a local one.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] A one-flag way to run any vm.sh flow / matrix cell on local HEAD
- [x] Every run prints the repo URL and commit it installs
- [x] docs (vm-agent-control / matrix) say which source a run installs

## Comments

2026-10-12: `vm.sh --local` / `matrix.sh run|smoke --local` (= `REPO_URL=local`)
stage a bare clone of local HEAD in CACHE_DIR and serve it on the gateway
(vm/lib/repo-source.sh; the Feature Audit reuses it). The matrix stages and
serves once per run (parallel cells share the port). Every install flow
prints `Repo source: …` (URL + commit; a pushed repo is flagged). Docs:
vm/README.md, combination-matrix.md, vm-agent-control.md. Covered by
tests/vm/repo-source.bats; VM-proven: `matrix.sh run --local
zfs-single-plain` announced `local HEAD 4abcae33` and the guest cloned
`http://192.168.122.1:9876/local-repo.git`; install + boot verify green
(first try hit the 45-min light band on slow mirrors; rerun with
MATRIX_TIMEOUT_LIGHT=5400).
