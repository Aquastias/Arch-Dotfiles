# source-for-dev.awk — the backing file of one target disk in a libvirt domain
# XML, where source and target sit on one line: the file= value on the first
# line carrying dev=<ENVIRON["DEVICE"]>. Quote-agnostic (virsh emits single
# quotes; the too-few fixture uses double).

# The line with that dev=: print its file= value and stop.
$0 ~ ("dev=[\047\"]" ENVIRON["DEVICE"] "[\047\"]") {
  if (match($0, /file=[\047"][^\047"]*[\047"]/))
    print substr($0, RSTART + 6, RLENGTH - 7)
  exit
}
