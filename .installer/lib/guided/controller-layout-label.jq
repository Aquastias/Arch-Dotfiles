# controller-layout-label.jq — the one-line disk layout description for the
# Disks "Disk layout" row: "single disk", or the OS pool's disk count and
# topology followed by each storage group's and data pool's.

# group(g) — " + <name>: <n> disks (<topology>)" for one pool group.
def group(g): " + \(g.name): \(g.disk_count) disks (\(g.topology))";

if (.mode // "single") != "multi" then "single disk"
else
  "OS: \(.os_pool.disk_count // "?") disks (\(.os_pool.topology // "?"))"
  + ((.storage_groups // []) | map(group(.)) | join(""))
  + ((.data_pools // []) | map(group(.)) | join(""))
end
