# report-noise.jq — the Known Noise entries as TAB-separated rows:
# regex, source, phase, variants (comma-joined; empty = every variant).
# An array regex is one regex split across lines (so the file keeps 80
# columns): its parts are joined. Not @tsv: it escapes the regexes'
# backslashes.
.[]
| [(.regex | if type == "array" then join("") else . end),
   (.source // ""), (.phase // ""), ((.variants // []) | join(","))]
| join("\t")
