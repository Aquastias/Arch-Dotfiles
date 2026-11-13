# generator-tier1-slug.jq — a stable, readable cell id from a Tier-1 cell's
# storage axes: <fs>-<topology>-<enc|plain>[-imp][-pool-<fs>[-penc]].
# zfs/single/plain/no-pool ⇒ "zfs-single-plain".

# Encryption, impermanence and the data pool, each as its id part.
(if .encryption then "enc" else "plain" end) as $enc
| (if .impermanence then "-imp" else "" end) as $imp
| (if .data_pool == null then ""
   else "-pool-" + .data_pool.filesystem
        + (if .data_pool.encryption then "-penc" else "" end) end) as $pool
# The parts joined.
| "\(.filesystem)-\(.topology)-\($enc)\($imp)\($pool)"
