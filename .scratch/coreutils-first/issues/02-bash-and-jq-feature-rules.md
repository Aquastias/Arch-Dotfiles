# 02: Bash and jq feature rules

**What to build:** The Readability Lint flags banned Bash Feature Tier
constructs (`${!ref}`, `declare -n`, `eval`, `<<<`, `BASH_REMATCH`,
`${var//a/b}`, `##`/`%%` pattern ops outside the self-locating bootstrap
line, `printf -v`, `${var@Q}`) as `bash-feature`, and banned jq features
inside jq programs (`reduce`, `foreach`, `walk`, `def`, `paths`,
`getpath`, `setpath`, `inputs`) as `jq-feature`. Commented `.jq` files are
the allowed home for jq that bash cannot express. The Tool Reference gains
Bash Feature Tier and jq feature sections listing the allowed forms with
meaning and example. Both rules honor Migrated Areas.

**Blocked by:** 01

**Status:** done

- [x] `bash-feature` and `jq-feature` rules with fixtures per banned form
- [x] Bootstrap `${path%/*}` line allowed; same form elsewhere flagged
- [x] jq look-alikes in strings/comments not flagged
- [x] `.jq` files allowed only with a header comment
- [x] Tool Reference Bash Feature Tier + jq sections
- [x] Strict whole-repo lint test still green
