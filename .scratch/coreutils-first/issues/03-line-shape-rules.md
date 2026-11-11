# 03: Line-shape rules

**What to build:** The Readability Lint enforces one step per line:
`inline-awk` (awk with an inline program), `sed-form` (sed other than
`-i` with one `s///`), `pipeline-length` (more than 2 `|`),
`chain-length` (more than 2 `&&`/`||`), `program-length` (inline jq/sed
program over ~40 characters), `what-comment` (jq/awk/sed program or
2-pipe pipeline with no comment line directly above). A `readability-ok:
perf` exemption must carry a `<before>→<after>` measurement. `.awk` files
need a header comment. The old `tool` and `sed-not-inplace` rules are
retired. All new rules honor Migrated Areas.

**Blocked by:** 01

**Status:** done

- [x] Each rule reports `rule: file:line: detail` with violating and clean
      fixtures
- [x] Multi-line pipelines/chains (backslash continuation) counted as one
- [x] `perf` exemption without a measurement is flagged
- [x] Old `tool` / `sed-not-inplace` rules and their tests removed
- [x] Strict whole-repo lint test still green
