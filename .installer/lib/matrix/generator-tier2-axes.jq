# generator-tier2-axes.jq — the install-affecting pairwise axes, each with its
# value set. Run with -n.
#
# Arguments: $fs the built root filesystems, $topo the root topologies (both
# JSON arrays).
{
  filesystem:   $fs,
  topology:     $topo,
  encryption:   [false, true],
  impermanence: [false, true],
  kernel:       ["lts", "zen"],
  bootloader:   ["systemd-boot", "grub", "efistub", "limine", "refind"],
  desktop:      ["none", "kde", "hyprland"],
  gpu:          ["auto", "amd", "nvidia", "intel"],
  swap:         [true, false]
}
