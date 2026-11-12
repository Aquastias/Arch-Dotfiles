# lib/packages/iso-resolver-pick.jq — the iso_url of the newest available
# Arch release whose kernel is not newer than the archzfs ceiling (ADR 0023).
# Input: the releng releases JSON (newest release first). $max: the ceiling
# kernel as major.minor ("6.19"). Prints nothing when no release fits.
#
# Kernels compare as numbers, field by field: 6.9 < 6.19, and 6.190 does
# not slip under a 6.19 ceiling.

# The ceiling as numbers: "6.19" → [6, 19].
($max | split(".") | map(tonumber)) as $cap
| .releases
| map(select(.available == true))
# Keep the releases whose kernel major.minor is at or below the ceiling.
| map(select(
    (.kernel_version | split(".") | map(tonumber)) as $k
    | ($k[0] < $cap[0]) or ($k[0] == $cap[0] and $k[1] <= $cap[1])
  ))
| (.[0].iso_url // empty)
