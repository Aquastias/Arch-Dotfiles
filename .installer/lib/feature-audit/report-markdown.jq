# report-markdown.jq — the Findings (read with -s) as markdown: a section per
# phase, a subsection per source, a bullet per Finding with its excerpt, logs
# and repro command. Phases and sources keep first-id order.

# finding — one Finding's bullet.
def finding:
  "\n- **\(.id)** [\(.variants | join(", "))] "
  + (if .program then "program=\(.program) " else "" end)
  + (if .check then "check=\(.check) " else "" end)
  + "seen \(.count)/\(.total) (\(.phases | join(", ")))\n"
  + "  ```\n  \(.excerpt)\n  ```\n"
  + "  logs: \(.logs | join(" "))\n"
  + "  repro: `\(.repro)`";

group_by(.phase) | sort_by(.[0].id) | .[]
| "\n## \(.[0].phase)\n"
  + (group_by(.source) | sort_by(.[0].id)
     | map("\n### \(.[0].source)\n" + (map(finding) | join("\n")))
     | join("\n"))
