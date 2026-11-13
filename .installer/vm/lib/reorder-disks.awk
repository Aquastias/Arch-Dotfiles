# reorder-disks.awk — a libvirt domain XML with the data disks' backing files
# reversed (the OS disk, the first, stays): the multi-disk reorder repro
# (ADR 0028). Fewer than three disks: the XML unchanged.

# The single-quote attribute delimiter (\047), no data disk seen yet.
BEGIN { quote = "\047"; disks = 0 }

# Keep every line; track whether it is inside a (non-cdrom) <disk>, and note
# each data disk's <source file=…/> line and backing file, in declared order.
{
  lines[NR] = $0
  if ($0 ~ "<disk[ >]") {
    is_cdrom = ($0 ~ ("device=" quote "cdrom" quote)) ? 1 : 0
    in_disk  = 1
  }
  source_attribute = "file=" quote "[^" quote "]*" quote
  if (in_disk && !is_cdrom && match($0, source_attribute)) {
    disks++
    source_line[disks] = NR
    # The path without `file=` and its quotes.
    files[disks] = substr($0, RSTART + 6, RLENGTH - 7)
  }
  if ($0 ~ "</disk>") { in_disk = 0; is_cdrom = 0 }
}

# Print the XML with the data disks' files swapped into reverse order.
END {
  if (disks < 3) { for (i = 1; i <= NR; i++) print lines[i]; exit }
  new_order[1] = files[1]
  j = 2
  for (i = disks; i >= 2; i--) new_order[j++] = files[i]
  for (k = 1; k <= disks; k++) replacement[source_line[k]] = new_order[k]
  for (i = 1; i <= NR; i++) {
    if (!(i in replacement)) { print lines[i]; continue }
    path = replacement[i]
    # Escape the characters sub() treats specially in a replacement.
    gsub(/[&\\]/, "\\\\&", path)
    text = lines[i]
    sub(("file=" quote "[^" quote "]*" quote), ("file=" quote path quote), text)
    print text
  }
}
