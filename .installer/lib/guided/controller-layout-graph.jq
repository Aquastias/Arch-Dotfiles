# controller-layout-graph.jq — the layout as an ASCII tree for the preview
# pane: one "▸ name (role)" branch per pool, its topology and disk count
# beneath.

# pool(name; role; topology; n) — one pool's branch and leaf.
def pool(name; role; topology; n):
  "  ▸ \(name)  (\(role))\n      └─ "
  + (if topology == null or topology == "none" then "\(n) disk(s)"
     else "\(topology) · \(n) disk(s)" end);

if (.mode // "single") != "multi" then
  "Single-disk ZFS\n\n" + pool("rpool"; "OS root"; null; 1)
else
  "Multi-disk ZFS\n\n"
  + pool(.os_pool.pool_name // "rpool"; "OS root";
         .os_pool.topology; .os_pool.disk_count)
  + ((.storage_groups // [])
     | map("\n" + pool(.name; "storage → \(.mount)"; .topology; .disk_count))
     | join(""))
  + ((.data_pools // [])
     | map("\n" + pool(.name; "data pool"; .topology; .disk_count))
     | join(""))
end
