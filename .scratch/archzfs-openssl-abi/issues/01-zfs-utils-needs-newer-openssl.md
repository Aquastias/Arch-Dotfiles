# 01: zfs-utils from archzfs needs a newer OpenSSL than the live ISO has

**What to build:** The ZFS bootstrap leaves a working `zpool` on the live
ISO even when archzfs's zfs-utils was built against a newer OpenSSL than
the ISO ships. Today pool creation dies with
`zpool: error while loading shared libraries: libcrypto.so.4`.

Seen 2026-11-11 (VM `desktop/combined-sops-impermanence`, local HEAD
20a113b): ISO openssl 3.6.5-1, archzfs zfs-utils 2.4.4-3 (wants
libcrypto.so.4). The bootstrap's `pacman -S --needed dkms zfs-dkms
zfs-utils` is a partial upgrade: it pulls zfs-utils without the OpenSSL it
links against. Unrelated to the ADR 0167 refactor (that step is unchanged).

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Root cause confirmed (archzfs rebuild against OpenSSL 4 vs the ISO's
      Arch snapshot), fix grounded on the Arch Wiki (partial upgrades)
- [x] The bootstrap installs a zfs-utils whose libraries resolve, or pulls
      the matching openssl
- [x] A VM install of `desktop/combined-sops-impermanence` creates pools
