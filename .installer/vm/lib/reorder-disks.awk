# reorder-disks.awk — a libvirt domain XML with the data disks' backing files
# reversed (the OS disk, the first, stays): the multi-disk reorder repro
# (ADR 0028). Fewer than three disks: the XML unchanged.

# The single-quote attribute delimiter (\047), no data disk seen yet.
BEGIN { q = "\047"; nd = 0 }

# Keep every line; track whether it is inside a (non-cdrom) <disk>, and note
# each data disk's <source file=…/> line and backing file, in declared order.
{
  lines[NR] = $0
  if ($0 ~ "<disk[ >]") {
    iscd   = ($0 ~ ("device=" q "cdrom" q)) ? 1 : 0
    indisk = 1
  }
  if (indisk && !iscd && match($0, ("file=" q "[^" q "]*" q))) {
    nd++; idx[nd] = NR
    files[nd] = substr($0, RSTART + 6, RLENGTH - 7)   # strip file= and delims
  }
  if ($0 ~ "</disk>") { indisk = 0; iscd = 0 }
}

# Print the XML with the data disks' files swapped into reverse order.
END {
  if (nd < 3) { for (i = 1; i <= NR; i++) print lines[i]; exit }
  neworder[1] = files[1]; j = 2
  for (i = nd; i >= 2; i--) neworder[j++] = files[i]
  for (k = 1; k <= nd; k++) repl[idx[k]] = neworder[k]
  for (i = 1; i <= NR; i++) {
    if (i in repl) {
      r = repl[i]; gsub(/[&\\]/, "\\\\&", r)          # escape sub() replacement
      s = lines[i]
      sub(("file=" q "[^" q "]*" q), ("file=" q r q), s)
      print s
    } else print lines[i]
  }
}
