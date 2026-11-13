# synth-profile.jq — a matrix cell's ephemeral VM Profile. Run with -n.
#
# Arguments: $name the VM name, $ram its RAM (MiB), $n how many disks, $gib
# each disk's size, $verify the verify block (null: install-only), $timeout
# the install timeout (s), $install the assembled Effective Config.
{
  name: $name,
  hardware: {disks: [range(0; $n) | $gib], ram_mb: $ram, vcpus: 2},
  timeouts: {install: $timeout},
  install: $install
}
# The verify block, unless the cell is install-only.
| if $verify != null then . + {verify: $verify} else . end
