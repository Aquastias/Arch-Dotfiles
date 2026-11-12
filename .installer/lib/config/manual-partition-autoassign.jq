# lib/config/manual-partition-autoassign.jq — give "/" to the largest
# unassigned partition (ext4 when it has no filesystem, formatted), unless a
# partition is already mounted at "/". Input and output: the assignment table.

if any(.[]; .mountpoint == "/") then .
else
  # The largest partition with no mountpoint (null when there is none).
  ( [ to_entries[] | select(.value.mountpoint == "") ]
    | sort_by(.value.size) | last ) as $pick
  | if $pick == null then .
    else .[$pick.key].mountpoint = "/"
         | (if (.[$pick.key].fs // "") == "" then .[$pick.key].fs = "ext4"
            else . end)
         | .[$pick.key].format = true
    end
end
