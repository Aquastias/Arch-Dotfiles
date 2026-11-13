# sops-vm-recipient.awk — the VM-fixture rule's age recipient in .sops.yaml:
# the first age1… line after the `/vm/` path_regex line.

# The VM rule's path_regex: the recipient follows.
/path_regex:.*\/vm\// { found = 1; next }

# Its first age1 recipient line, whitespace dropped.
found && /^[[:space:]]*age1[a-z0-9]+[[:space:]]*$/ {
  gsub(/[[:space:]]/, ""); print; exit
}
