# generator-tier2-slug.jq — a stable id for a pairwise (Tier-2) cell from its
# row: every install-affecting axis, in a fixed order.
"t2-\(.filesystem)-\(.topology)"
+ (if .encryption then "-enc" else "-plain" end)
+ (if .impermanence then "-imp" else "" end)
+ "-k\(.kernel)-b\(.bootloader)-d\(.desktop)-g\(.gpu)"
+ (if .swap then "-swap" else "-noswap" end)
