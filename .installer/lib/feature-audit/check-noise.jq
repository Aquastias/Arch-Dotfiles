# check-noise.jq — the problems of a Known Noise file, one message per line.
# Every entry needs a reason, and its optional `variants` list must be an
# array of real manifest variant ids.
#
# Arguments: $ids — the manifest's variant ids (a JSON array).

if type != "array" then "noise: not a JSON array"
else
  .[]
  # The entry's regex, joined when it is written as an array of parts.
  | (.regex // "?" | if type == "array" then join("") else . end) as $r
  # A missing or empty reason.
  | (if (.reason // "") == "" then "noise: \($r) has no reason"
     else empty end),
  # A variants scope that is not a list, or names an unknown variant.
    (if .variants == null then empty
     elif (.variants | type) != "array"
     then "noise: \($r) variants not an array"
     else .variants[] | select(. as $v | $ids | index($v) | not)
       | "noise: \($r) names unknown variant \(.)" end)
end
