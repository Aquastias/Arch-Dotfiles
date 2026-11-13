# generator-seeds.jq — the pinned historical-bug cells (ADR 0046), one per
# output, so a known regression can never silently drop out of Tier 2. Run
# with -n -c.

# zfs root + btrfs data pool (mixed-fs, the classic bug-dense case).
{id: "seed-zfs-root-btrfs-pool", tier: 2, axes: {
  filesystem: "zfs", mode: "single", topology: "single", disk_count: 1,
  encryption: false, impermanence: false,
  data_pool: {filesystem: "btrfs", encryption: false, topology: "single",
              disk_count: 1}}},
# ext4 root + zfs data pool (mixed-fs, the other direction).
{id: "seed-ext4-root-zfs-pool", tier: 2, axes: {
  filesystem: "ext4", mode: "single", topology: "single", disk_count: 1,
  encryption: false, impermanence: false,
  data_pool: {filesystem: "zfs", encryption: false, topology: "none",
              disk_count: 1}}},
# xfs root (the modprobe-before-root-mount case).
{id: "seed-xfs-root", tier: 2, axes: {
  filesystem: "xfs", mode: "single", topology: "single", disk_count: 1,
  encryption: false, impermanence: false, data_pool: null}},
# zfs keyfile-on-root + encrypted pool (root plaintext, pool key on root).
{id: "seed-zfs-keyfile-root-enc-pool", tier: 2, axes: {
  filesystem: "zfs", mode: "single", topology: "single", disk_count: 1,
  encryption: false, impermanence: false,
  data_pool: {filesystem: "zfs", encryption: true, topology: "none",
              disk_count: 1}}},
# nvidia × kernel: pin the DKMS-against-headers build for each kernel.
(("lts", "zen") as $k
 | {id: ("seed-nvidia-k" + $k), tier: 2, axes: {
     filesystem: "zfs", mode: "single", topology: "single", disk_count: 1,
     encryption: false, impermanence: false, data_pool: null,
     kernel: $k, bootloader: "systemd-boot", desktop: "kde", gpu: "nvidia",
     swap: true}})
