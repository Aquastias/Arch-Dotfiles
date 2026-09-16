# 03: Reworked `statusline.sh`

**What to build:** The statusline reads the data Claude Code now exposes
natively and shows the operator's approved layout (emoji icon set, per the
`.scratch/claude-code-config/statusline-prototype.sh` prototype — `emoji` won
over `nerd`). It replaces the old transcript-tailing cache hack and adds a
plan-usage meter, so at a glance the operator sees model+effort, dir, dirty
branch, sandbox, plan, context, cache, 5-hour usage, duration, and churn.

**Blocked by:** 01 (the tracked script must exist to rework).

**Status:** ready-for-agent

- [ ] 5-hour meter from `rate_limits.five_hour.used_percentage` + a `resets_at`
      countdown, colored (green<50/yellow<80/red); replaces the `$cost` segment
      on subscription plans, `$cost` retained on API plans
- [ ] Cache-hit from `prompt_cache.hit_ratio` (transcript-tail block deleted)
- [ ] `effort.level` shown beside the model
- [ ] `cost.total_lines_added/removed` render green add / red delete
- [ ] Red dot beside the branch when `git status --porcelain` is non-empty,
      with a space before the dot
- [ ] Emoji icon set; colors on the ANSI-16 palette (ADR 0132)
- [ ] `ccusage` burn detail as a second segment, refreshed at most every ~30s
      via an mtime-checked tmp cache; absent `ccusage`, the segment is empty and
      the native meter still renders
- [ ] Existing sandbox / plan / branch / context-bar / duration segments
      retained
