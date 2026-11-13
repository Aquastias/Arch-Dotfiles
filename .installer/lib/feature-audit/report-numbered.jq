# report-numbered.jq — the entries (read with -s) of one severity, each given
# an id: <prefix><n>, n zero-padded to at least 3 digits (more when there are
# over 999 of them).
#
# Arguments: $sev the severity kept, $p the id prefix (F or A).

map(select(.severity == $sev))
# The id width: 3, or the count's digit count when larger.
| ([length, 999] | max | tostring | length) as $w
| to_entries
| map(.value + {id: ($p + ((.key + 1) | tostring | ("0" * $w + .) | .[-$w:]))})
| .[]
