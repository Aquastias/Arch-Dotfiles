# aur-trust-clean.awk — the input with every control character shown as `?`:
# the AUR RPC answer and the package repo are attacker text, and must not
# drive the terminal.

# Replace each control character on the line.
{ gsub(/[[:cntrl:]]/, "?"); print }
