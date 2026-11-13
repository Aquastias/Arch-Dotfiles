# driver-summary.jq — the matrix run summary from the result records (run
# with -s: the records as one array). One TAB-separated row per cell (status,
# id, axes, oracle), a re-run hint under every FAIL, then the tally.

# count(s) — how many cells ended with status s.
def count(s): [.[] | select(.status == s)] | length;

# A row per cell, its re-run hint below when it failed.
(.[] | "\(.status)\t\(.id)\t\(.axes)\t\(.oracle)"
   + (if .status == "FAIL" then "\n      re-run: matrix.sh run \(.id)"
      else "" end)),
"----",
# The tally.
"totals: PASS=\(count("PASS")) FAIL=\(count("FAIL")) SKIP=\(count("SKIP"))"
