# finalize-namespace-mounts.awk — the ZFS datasets of one pool mounted in a
# process's mount namespace, read from its /proc/<pid>/mountinfo (ADR 0043).
# Used by: lib/finalize.sh (_finalize_namespace_pool_mounts).
#
# Input: mountinfo lines. Each holds optional fields, then a lone "-", then
# the filesystem type and the mount source:
#   36 35 0:30 / /mnt/home rw shared:9 - zfs rpool/home rw
# Variables (awk -v): pool, pid, command.
# Output, per matching mount: <pid> <command> mount-ns <mount point> <source>

# Find the "-" that ends the optional fields; the type and source follow it.
{
  for (field = 1; field <= NF; field++) if ($field == "-") break
  filesystem = $(field + 1)
  source = $(field + 2)
}

# A zfs mount of the pool itself, one of its datasets, or a snapshot.
filesystem == "zfs" && (source == pool || index(source, pool "/") == 1 ||
                        index(source, pool "@") == 1) {
  print pid, command, "mount-ns", $5, source
}
