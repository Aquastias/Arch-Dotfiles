# report-finding.jq — one aggregated candidate row (TSV, read with -R) as a
# Finding object. The row's fields: phase-rank, source, program, check,
# phases, variants, count, total, excerpt, logs, severity.
#
# Arguments: $run the run folder, $va the {variant: [adr…]} map.

split("\t") as $f
# The variants that saw it.
| ($f[5] | split(",")) as $variants
| { phase: ($f[4] | split(",")[0]), phases: ($f[4] | split(",")),
    source: $f[1],
    program: (if $f[2] == "" then null else $f[2] end),
    check: (if $f[3] == "" then null else $f[3] end),
    variants: $variants, count: ($f[6] | tonumber),
    total: ($f[7] | tonumber), excerpt: $f[8],
    # Each log path, inside the run folder.
    logs: ($f[9] | split(",") | map($run + "/" + .)),
    # The ADRs every one of its variants exists to cover, each once.
    adrs: ([$variants[] | $va[.] // [] | .[]] | unique),
    # The command that reruns the first variant, held for inspection.
    repro: ("tools/feature-audit.sh run --variant " + $variants[0] + " --keep"),
    severity: $f[10] }
