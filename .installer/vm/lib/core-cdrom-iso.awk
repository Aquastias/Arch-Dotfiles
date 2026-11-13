# core-cdrom-iso.awk — the .iso source file of the first cdrom in a libvirt
# domain XML (`virsh dumpxml`), or nothing when no cdrom has one.

# The attribute patterns, single-quoted as virsh writes them.
BEGIN {
  q = "'"
  start = "device=" q "cdrom" q
  source = "source file=" q "[^" q "]+\\.iso" q
}

# A cdrom <disk> opens.
!in_disk && $0 ~ start { in_disk = 1; first = 1 }

# Its source file: print the path inside the quotes and stop.
in_disk && match($0, source) {
  print substr($0, RSTART + 13, RLENGTH - 14); exit
}

# The <disk> closes (not on its opening line).
in_disk && !first && /<\/disk>/ { in_disk = 0 }

# Past the opening line.
{ first = 0 }
