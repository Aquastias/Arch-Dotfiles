# sops-recipient.awk — .sops.yaml with the VM-fixture rule's age recipient
# (the first age1… line after the `/vm/` path_regex line) replaced by `pub`;
# every other line, the operator placeholder rule included, byte-for-byte.
# Exits 3 when no such rule is found. Variable: pub.

# The VM rule's recipient line: the new key, same indent.
found && !done && /^[[:space:]]*age1[a-z0-9]+[[:space:]]*$/ {
  match($0, /^[[:space:]]*/); print substr($0, 1, RLENGTH) pub
  done = 1; found = 0; next
}

# The VM rule's path_regex: its recipient follows.
/path_regex:.*\/vm\// { found = 1 }

# Every line passes through.
{ print }

# No VM rule found.
END { if (!done) exit 3 }
