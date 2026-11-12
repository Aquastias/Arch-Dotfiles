# lib/config/manual-partition-scan.jq — the partitions of an `lsblk -J`
# tree as the Manual Partitioning assignment table (ADR 0073). Input: the
# lsblk JSON. $esp / $swap: the ESP and swap GPT type GUIDs.
# Output: [{device, size, mountpoint, fs, format}].

# Every partition, at any depth of the tree.
[ .blockdevices | .. | objects | select(.type? == "part") ]
| map(
    ((.parttype // "") | ascii_downcase) as $pt
  | ((.parttypename // "") | ascii_downcase) as $pn
  | (.fstype // "") as $fst
  # An ESP or a swap partition, by type GUID, type name or filesystem.
  | (($pt == $esp) or ($pn | test("efi")) or ($fst == "vfat")) as $is_esp
  | (($pt == $swap) or ($pn | test("swap")) or ($fst == "swap")) as $is_swap
  # ESP and swap come pre-filled; a partition with no filesystem is formatted.
  | { device: .path,
      size: (.size // 0),
      mountpoint: (if $is_esp then "/boot/efi"
                   elif $is_swap then "[swap]" else "" end),
      fs:     (if $is_esp then "fat32"
               elif $fst != "" then $fst else "" end),
      format: ($fst == "") }
  )
