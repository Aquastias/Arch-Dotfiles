# Core curation — edit the `layer` column

Set each row's `layer`, then tell me it's ready. I apply the result to the
profiles. All flags are resolved — see [Resolved](#resolved) at the bottom.

## Layers

| value    | meaning                                                       |
|----------|---------------------------------------------------------------|
| `L0`     | Base Package List (`lib/packages/list.sh`) — installer needs it|
| `core`   | `hosts/core` — the shared base every real host inherits        |
| `desk`   | `hosts/desktop` only                                           |
| `lap`    | `hosts/laptop` only                                            |
| `derive` | computed from another setting — stop declaring it              |
| `drop`   | remove — duplicate, adapter-owned, or orphaned                 |

**Two layers, core → host** (R20). The VM fixtures opt out with
`packages.inherit: false`, so core is free to hold your full workstation
userland without bloating the test installs. `hosts/laptop` ends up with no
packages block at all — it is a strict subset of desktop, so everything it
wants *is* core.

Because the fixtures opt out wholesale, the earlier "core carries no AUR" rule
is moot — core holds 5 AUR entries and no fixture builds them.

## Totals

| layer  | repo | aur | total |
|--------|-----:|----:|------:|
| core   |   55 |   6 |    61 |
| desk   |   27 |   7 |    34 |
| derive |    6 |   0 |     6 |
| drop   |   20 |  19 |    39 |
| L0     |    1 |   0 |     1 |
| **141**|  109 |  32 |   141 |

141, not 139: `pacmanlogviewer` and `octopi` join from the KDE adapter (R21).

---

## repo / system

| pkg            | layer  | why                                    |
|----------------|--------|----------------------------------------|
| stow           | `L0`   | runner hard-depends on it — R1         |
| fwupd          | `core` | firmware updates                       |
| logrotate      | `core` | universal; desktop-only today R2       |
| lsb-release    | `core` |                                        |
| reflector      | `core` | mirror ranking                         |
| smartmontools  | `core` | disk health                            |
| sbctl          | `core` | secure-boot keys                       |
| sof-firmware   | `core` | audio firmware                         |
| pacmanlogviewer| `core` | from the KDE adapter — R21             |
| stress         | `desk` | benchmarking                           |
| stress-ng      | `desk` | benchmarking                           |
| tectonic       | `desk` | LaTeX engine, large                    |
| zram-generator | `drop` | ADR 0045 rejected zram — R3            |
| uwsm           | `drop` | Hyprland-era, unused under KDE — R4    |

## repo / filesystems

| pkg            | layer    | why                     |
|----------------|----------|-------------------------|
| exfatprogs     | `core`   | USB sticks              |
| lvm2           | `core`   |                         |
| f2fs-tools     | `core`   | SD cards / flash        |
| btrfs-progs    | `derive` | from `filesystem` — R5  |
| xfsprogs       | `derive` | from `filesystem` — R5  |
| bcachefs-tools | `desk`   | exotic                  |
| jfsutils       | `desk`   | exotic                  |
| nilfs-utils    | `desk`   | exotic                  |
| udftools       | `desk`   | optical                 |
| fatresize      | `desk`   | exotic                  |

## repo / network

| pkg                    | layer  | why                                  |
|------------------------|--------|--------------------------------------|
| wget                   | `core` | rkhunter is optional — R18 keep      |
| openbsd-netcat         | `core` | tiny; desktop-only today R2          |
| iwd                    | `core` | wifi                                 |
| network-manager-applet | `core` | tray                                 |
| dnsmasq                | `desk` | libvirt NAT; pair with the virt block|
| nftables               | `drop` | dep of `base` — R18                  |
| iptables               | `drop` | dep of `base` as well — R6, R18      |
| wireless_tools         | `drop` | deprecated (iwconfig) — R7           |

## repo / shell

| pkg      | layer    | why                               |
|----------|----------|-----------------------------------|
| bc       | `core`   |                                   |
| btop     | `core`   |                                   |
| eza      | `core`   |                                   |
| fd       | `core`   | desktop-only today R2             |
| fzf      | `core`   | desktop-only today R2             |
| htop     | `core`   |                                   |
| inxi     | `core`   |                                   |
| kitty    | `core`   | terminal emulator                 |
| lazygit  | `core`   | desktop-only today R2             |
| lynx     | `core`   |                                   |
| nano     | `core`   |                                   |
| parallel | `core`   |                                   |
| yazi     | `core`   | file manager                      |
| zoxide   | `core`   | `.zshrc` calls `zoxide init`      |
| zsh      | `derive` | from the login shell setting — R8 |
| less     | `drop`   | dep of `man-db` — R18             |

## repo / editors

| pkg     | layer  | why                        |
|---------|--------|----------------------------|
| neovim  | `core` | desktop-only today R2      |
| neovide | `core` | GUI nvim                   |
| zed     | `drop` |                            |

## repo / dev

| pkg             | layer  | why                                  |
|-----------------|--------|--------------------------------------|
| ccache          | `core` |                                      |
| nvm             | `core` | `.zsh/vendors/nodejs/nvm` expects it |
| biome           | `desk` |                                      |
| go              | `desk` | sops Program installs it when needed |
| mermaid-cli     | `desk` |                                      |
| python-pip      | `desk` |                                      |
| python-pipx     | `desk` |                                      |
| tree-sitter-cli | `desk` |                                      |
| docker          | `drop` | it's a Program — R9                  |
| docker-compose  | `drop` | fold into the docker Program — R9    |

## repo / desktop

All four are DE-tied — ADR 0021 gives them to the KDE adapter. See R10.

| pkg                | layer  | why           |
|--------------------|--------|---------------|
| papirus-icon-theme | `drop` | → KDE adapter |
| qt5-wayland        | `drop` | → KDE adapter |
| qt6-wayland        | `drop` | → KDE adapter |
| xdg-utils          | `drop` | → KDE adapter |

## repo / browsers

| pkg     | layer  | why |
|---------|--------|-----|
| firefox | `core` |     |

## repo / media

| pkg                 | layer    | why                                |
|---------------------|----------|------------------------------------|
| imagemagick         | `core`   | desktop-only today R2              |
| gimp                | `core`   |                                    |
| speech-dispatcher   | `core`   |                                    |
| vlc                 | `core`   |                                    |
| pavucontrol         | `core`   | GTK mixer; KDE ships its own       |
| gst-plugin-pipewire | `derive` | → derived audio set — R11          |
| pipewire-jack       | `derive` | → derived audio set — R11          |
| libpulse            | `derive` | → derived audio set — R11          |
| qbittorrent         | `desk`   | KDE adapter already ships ktorrent |
| vlc-plugin-freetype | `desk`   |                                    |
| vlc-plugin-notify   | `desk`   |                                    |
| vlc-plugin-srt      | `desk`   |                                    |
| flatpak             | `drop`   | dep of `plasma-meta` — R18         |
| libavif             | `drop`   | dep of `qemu-full`/skanlite — R18  |

## repo / communication

| pkg        | layer  | why                                  |
|------------|--------|--------------------------------------|
| discord    | `core` |                                      |
| teamspeak3 | `drop` | Program, and it's AUR not repo — R12 |

## repo / gaming

| pkg            | layer  | why                          |
|----------------|--------|------------------------------|
| gamemode       | `core` |                              |
| lib32-gamemode | `core` |                              |
| steam          | `core` |                              |
| lact           | `desk` | AMD overclocking             |
| lutris         | `desk` |                              |
| wine           | `desk` | dep of gecko/mono — R18 keep |
| wine-gecko     | `desk` |                              |
| wine-mono      | `desk` |                              |

## repo / virt

| pkg          | layer  | why                           |
|--------------|--------|-------------------------------|
| qemu-full    | `desk` |                               |
| libguestfs   | `desk` |                               |
| virt-viewer  | `desk` |                               |
| virt-manager | `drop` | it's a Program — R9           |
| qemu-base    | `drop` | qemu-full supersedes it — R13 |
| vde2         | `drop` | dep of `qemu-full` — R18      |

## repo / archive

| pkg   | layer  | why                            |
|-------|--------|--------------------------------|
| 7zip  | `core` |                                |
| arj   | `core` |                                |
| lhasa | `core` |                                |
| unace | `core` |                                |
| unarj | `core` |                                |
| unrar | `core` |                                |
| unzip | `core` | lutris is desk-only — R18 keep |
| zip   | `core` | desktop-only today R2          |
| cpio  | `drop` | dep of `base-devel` — R18      |

## repo / fonts

| pkg              | layer  | why |
|------------------|--------|-----|
| noto-fonts-cjk   | `core` |     |
| noto-fonts-extra | `core` |     |
| ttf-fira-code    | `core` |     |
| ttf-sazanami     | `core` |     |

## aur

All 17 catppuccin entries are **purged** — not relocated (R19). `qt6ct-kde` is
the one theming entry that survives, moving to the KDE adapter's own `aur` list
per ADR 0021 (R10).

| pkg                                      | layer  | why                 |
|------------------------------------------|--------|---------------------|
| ttf-ms-fonts                             | `core` |                     |
| vscodium-bin                             | `core` |                     |
| vscodium-marketplace                     | `core` |                     |
| zen-browser-bin                          | `core` |                     |
| ani-cli-git                              | `core` |                     |
| octopi                                   | `core` | from KDE adapter R21|
| brave-bin                                | `desk` |                     |
| bolt-launcher                            | `desk` | game launcher       |
| runelite                                 | `desk` | game launcher       |
| grayjay-bin                              | `desk` |                     |
| bridge-utils                             | `desk` | pairs with virt     |
| ckb-next-git                             | `desk` | Corsair keyboard    |
| lua-format                               | `desk` |                     |
| zinit                                    | `drop` | self-bootstraps R8  |
| qt6ct-kde                                | `drop` | → KDE adapter — R10 |
| btop-theme-catppuccin                    | `drop` | purged — R19        |
| catppuccin-cursors-frappe                | `drop` | purged — R19        |
| catppuccin-cursors-latte                 | `drop` | purged — R19        |
| catppuccin-cursors-macchiato             | `drop` | purged — R19        |
| catppuccin-cursors-mocha                 | `drop` | purged — R19        |
| catppuccin-gtk-theme-frappe              | `drop` | purged — R19        |
| catppuccin-gtk-theme-latte               | `drop` | purged — R19        |
| catppuccin-gtk-theme-macchiato           | `drop` | purged — R19        |
| catppuccin-gtk-theme-mocha               | `drop` | purged — R19        |
| catppuccin-konsole-colorscheme-mocha-git | `drop` | purged — R19        |
| catppuccin-plasma-colorscheme-mocha      | `drop` | purged — R19        |
| catppuccin-sddm-theme-frappe             | `drop` | purged — R19        |
| catppuccin-sddm-theme-latte              | `drop` | purged — R19        |
| catppuccin-sddm-theme-macchiato          | `drop` | purged — R19        |
| catppuccin-sddm-theme-mocha              | `drop` | purged — R19        |
| papirus-folders-catppuccin-git           | `drop` | purged — R19        |
| plymouth-theme-catppuccin-mocha-git      | `drop` | purged; R14 too     |

## Programs

| program           | layer        | why                                 |
|-------------------|--------------|-------------------------------------|
| cups              | `core`       | unchanged from today — R15 withdrawn|
| grub              | `desk`       | rescue GRUB + os-prober — R16       |
| sops              | —            | secrets-activated (ADR 0025)        |
| docker            | `users/core` | R17                                 |
| virt-manager      | `users/core` | R17                                 |
| podman            | `aquastias`  |                                     |
| searxng           | `aquastias`  |                                     |
| teamspeak3        | `aquastias`  |                                     |
| borg              | —            | host `post_install.backup` (0041)   |
| zfs-auto-snapshot | —            | host `post_install.backup` (0041)   |
| apparmor          | —            | host `post_install.security` (0041) |
| clamav            | —            | host `post_install.security` (0041) |
| firewalld         | —            | host `post_install.security` (0041) |
| rkhunter          | —            | host `post_install.security` (0041) |
| ufw               | —            | host `post_install.security` (0041) |

## KDE adapter — `extras/desktop/kde/install-kde.jsonc`

`apps_list` becomes **only** applications with an `apps.kde.org` page (R21).
The `plasma-extras` category disappears entirely.

| pkg                    | action              | why                            |
|------------------------|---------------------|--------------------------------|
| sddm-kcm               | → shell section     | KCM, not an app; not in meta   |
| xdg-desktop-portal-kde | remove              | `plasma-meta` already pulls it |
| kimageformats5         | remove              | KF5 leftover; see R21          |
| pacmanlogviewer        | → `hosts/core` repo | not KDE                        |
| octopi                 | → `hosts/core` aur  | not KDE; `aur` block goes away |

Resulting `apps_list` — 20 entries, unchanged from today apart from the five
above:

| category        | packages                                        |
|-----------------|-------------------------------------------------|
| file-management | ark dolphin filelight krename krusader          |
| documents       | calligra okular                                 |
| graphics        | gwenview krita skanlite skanpage                |
| development     | kate kdiff3 kompare keditbookmarks              |
| security        | kleopatra kwalletmanager                        |
| system          | konsole partitionmanager                        |
| network         | ktorrent                                        |

Also moving **into** the adapter, per R10: `papirus-icon-theme`, `qt5-wayland`,
`qt6-wayland`, `xdg-utils` (repo) and `qt6ct-kde` (aur). These are DE-tied but
are **not** applications — they belong in the shell section alongside
`sddm-kcm`, not in `apps_list`.

## Non-package changes this pulls in

- `users/core.shell` → `/bin/zsh`; guided default follows
  (`lib/config/seed.sh`). `options.root_shell` stays `/bin/bash` per ADR 0054.
- `_pipewire` in `lib/config/environment.sh:126` gains `gst-plugin-pipewire`,
  `pipewire-jack`, `libpulse`.
- `users/vm-test` and `users/vm-data` gain
  `programs_exclude: [docker, virt-manager]`.
- The 3 VM host fixtures gain `packages.inherit: false`.
- `stow` joins the Base Package List.
- `extras/desktop/kde/install-kde.jsonc`: `apps_list` reduced to real
  applications (R21); shell section in `kde.sh` gains `sddm-kcm` plus R10's 4
  repo + 1 AUR DE-tied entries; the `aur` block is removed.
- `tests/config/configs.bats:108` — the `desktop system_programs == ["grub"]`
  assertion changes. The `core system_programs == ["cups"]` assertion at :24
  now stands unchanged (R15 withdrawn).

---

## Resolved

**R1 `stow` is a latent install failure.** `lib/profiles/runner.sh:583-584` runs
`stow` unconditionally for every user, but it is not in the Base Package List —
only in `desktop`/`laptop`. Any host that doesn't declare it (all three VM
fixtures) hits `stow: command not found`. → `L0`.

**R2 desktop-only today, but nothing about it is desktop-specific.** `laptop`
simply never got these. Affects `logrotate`, `openbsd-netcat`, `fd`, `fzf`,
`lazygit`, `neovim`, `imagemagick`, `zip`.

**R3 zram — dropped.** ADR 0045 line 19 rejects it explicitly: *"Add zram —
rejected as a different feature; this decision is zswap."* Nothing writes
`zram-generator.conf`.

**R4 `uwsm` — dropped.** Referenced only in the two profiles. Hyprland-era
session manager; ADR 0050 made KDE+SDDM the only path.

**R5 `btrfs-progs` / `xfsprogs` are already derived** at
`lib/packages/list.sh:153-154` from the resolved filesystem.

**R6 `iptables`** conflicts-and-provides with `iptables-nft`; declaring it
beside `nftables` invites a replace-prompt during pacstrap. See also R18 — both
arrive via `base` regardless.

**R7 `wireless_tools`** is the deprecated `iwconfig` suite, superseded by `iw`
and `iwd`.

**R8 Shell → zsh; neither `zsh` nor `zinit` needs declaring.** The tracked
shell payload is entirely zsh (18 files under `.zsh/`, plus `.zshrc`,
`.zshenv`, `.zprofile`, `.zsh_aliases`, `.p10k.zsh`); `.bashrc`,
`.bash_profile` and `.profile` are untracked. `ensure_login_shell_installed`
(`lib/chroot/chroot-common.sh:39-51`) pacman-installs the login shell's package
when the binary is missing, so `shell: /bin/zsh` pulls zsh by itself → `derive`.
`.zsh/zinit/default.zsh:6-9` git-clones zinit if absent, so the AUR package is
redundant → `drop`. Note: that clone happens at first interactive shell, so the
first login after install needs network.

**R9 Program/package duplication.** Mutual exclusion is now validated at config
load. `docker`, `virt-manager` and `teamspeak3` were declared as raw repo
packages *and* as user Programs. `docker-compose` isn't a Program — folding it
into `programs/virtualization/docker/install.sh` rather than stranding it.

**R10 ADR 0021 already assigns DE-tied packages to the DE adapter**, including
its own `aur` list. After the catppuccin purge (R19) the relocation set is 4
repo (`papirus-icon-theme`, `qt5-wayland`, `qt6-wayland`, `xdg-utils`) + 1 AUR
(`qt6ct-kde`) → moved to `extras/desktop/kde/install-kde.jsonc` so they land
only when KDE is selected.

**R11 Audio folded into derivation.** `_pipewire`
(`lib/config/environment.sh:126`) gains `gst-plugin-pipewire`, `pipewire-jack`
and `libpulse` alongside `pipewire pipewire-pulse pipewire-alsa wireplumber`.

**R12 `teamspeak3` was in `packages.repo` but is an AUR package** — its Program
installs it with `${AUR_HELPER} -S` (`install.sh:18`). pacstrap would fail on
it. Live bug, fixed by the drop.

**R13 `qemu-base` and `qemu-full` both declared**; `qemu-full` is a superset.

**R14 `plymouth-theme-*` with no plymouth.** Nothing installs plymouth and no
ADR mentions a boot splash. Adding one properly (mkinitcpio hook, `quiet splash`
cmdline, interaction with the passphrase prompt and the Impermanence Rollback
Hook) is separate work.

**R15 Withdrawn.** `cups` moving out of core only made sense while a
workstation tier existed. Under two layers (R20) the fixtures opt out of core
packages wholesale, so `cups` stays exactly where it is today and
`tests/config/configs.bats:24` needs no change.

**R16 `grub` on `desktop` is deliberate — earlier flag withdrawn.**
`programs/bootloader/grub/config.jsonc` documents it: the Program exists "for
hosts that want to (re)apply grub via the declarative path or layer extra
config (os-prober)", and its `install.sh` runs `grub_install_and_configure`.
It's a rescue/dual-boot GRUB beside systemd-boot, and `configs.bats:108`
asserts that exact shape. Stays, layer `desk`.

**R17 `docker` + `virt-manager` → `users/core`**, with `programs_exclude` on
`vm-test` and `vm-data`.

**R18 Dependency audit.** Ran `pactree -su` over all 165 packages — the 88
repo-resolvable curated entries plus the 77 in the "already provided" set (Base
Package List, KDE adapter, derived audio/GPU, and the Program-installed
packages incl. security and backup). 12 curated entries turned out to be
transitive dependencies of something else, and 6 were safe to drop:

| pkg      | pulled in by                          |
|----------|---------------------------------------|
| cpio     | `base-devel` (L0)                     |
| less     | `man-db` (L0)                         |
| nftables | `base` (L0) → iproute2 → iptables-nft |
| flatpak  | `plasma-meta` (KDE)                   |
| libavif  | `qemu-full`, `skanlite`/`skanpage`    |
| vde2     | `qemu-full`, `libguestfs`             |

Kept despite being deps, because their parent is optional or higher-layer:
`lsb-release` (`steam`), `neovim` (`neovide`), `smartmontools` (`plasma-meta`),
`unzip` (`lutris`, desk-only), `wget` (`rkhunter`, opt-in security).

`nftables` also settles R6: `base` depends on `iproute2`, which needs
`libxtables.so`, provided by `iptables-nft`, which depends on `nftables`.

`wine` is the one judgment call. It is genuinely a dependency of `wine-gecko`
and `wine-mono`, so declaring it is redundant today — but it's the package you
actually want, and gecko/mono are its add-ons. Keeping it explicit means
dropping them later can't orphan it. Say the word and I'll drop it too.

Caveat: the AUR entries and the archzfs packages aren't in the local sync db,
so their dependency trees weren't resolvable. All are leaf applications.

Trade-off this accepts: a dropped package installs as a *dependency*, not
*explicit*. If its parent is ever removed, `pacman -Qdtq | pacman -Rns -` will
take it too. For all six that parent is guaranteed, so the risk is nil.

**R19 Catppuccin purged — packages only.** All 17 entries removed outright
rather than relocated: 4 `catppuccin-cursors-*`, 4 `catppuccin-gtk-theme-*`, 4
`catppuccin-sddm-theme-*`, `catppuccin-konsole-colorscheme-mocha-git`,
`catppuccin-plasma-colorscheme-mocha`, `papirus-folders-catppuccin-git`,
`plymouth-theme-catppuccin-mocha-git`, `btop-theme-catppuccin`.

`qt6ct-kde` and `papirus-icon-theme` are **not** catppuccin — they're the Qt6
config tool and the base icon set the catppuccin packages recoloured. Both
survive and move to the KDE adapter per R10.

The dotfiles side is deliberately **untouched**: 22 tracked theme files and
references in 9 configs stay as they are. Kitty and zsh-syntax-highlighting
keep working (their themes are self-contained files in the repo); the gtk,
sddm, plasma, konsole, cursor and papirus-folders surfaces fall back to stock,
since those themes came from the purged packages.

**R20 Workstation tier collapsed.** The three-tier model
(core → workstation → host) existed for one reason: the VM fixtures declare no
packages and inherit core, so GUI userland in core would have made every Tier 2
install pacstrap `steam`, `wine`, `gimp`, `firefox`. That is a test-fixture
problem, and it was buying itself a permanent concept in the config model.

`packages.inherit: false` on the three fixtures buys the same thing for one
key. So: no `hosts/base/`, no `extends`, no cycle detection, no multi-parent
resolution order. Two layers, core → host — the model that was already in place
before this work started.

Confirmation that two is the right number for this fleet: `hosts/laptop` ends
up with **no packages block at all**, because laptop is a strict subset of
desktop and everything it wants is core.

Superseded by this: the `hosts/base/` reserved directory, `extends` (array,
chaining, cycle detection), and Save Profile's "preserve the extends chain"
behaviour — Save now writes a plain delta over core, as it effectively did
before. `exclude` survives and is still needed, for a host that wants to drop
something core declares.

**R21 "KDE Applications" installs only KDE applications.** The adapter's
`apps_list` — the set behind the installer's `KDE Applications` section — held
five things that are not applications. Verified against
<https://apps.kde.org/> plus each package's `URL` and `Groups` fields, which
are decisive: a real KDE application carries `URL: https://apps.kde.org/<name>/`
and `Groups: kde-applications`, while Plasma pieces carry `Groups: plasma` and
`URL: https://kde.org/plasma-desktop/`.

| pkg                    | URL                            | Groups | verdict |
|------------------------|--------------------------------|--------|---------|
| sddm-kcm               | kde.org/plasma-desktop         | plasma | KCM     |
| xdg-desktop-portal-kde | kde.org/plasma-desktop         | plasma | portal  |
| kimageformats5         | community.kde.org/Frameworks   | kf5    | library |
| pacmanlogviewer        | github.com/gcala/…             | —      | not KDE |
| octopi (aur)           | github.com/aarnt/octopi        | —      | not KDE |

Only `sddm-kcm` actually needs relocating to the shell section. The other two
Plasma-side entries are **redundant**:

- `xdg-desktop-portal-kde` is already in `plasma-meta`'s dependency tree.
- `kimageformats5` is the **KF5** build (5.116.0) — a Plasma 5 leftover. Plasma
  6 uses `kimageformats` (6.28.1), which `plasma-meta` already pulls via
  `kscreen`. The declared package was doing nothing but installing a stale Qt5
  parallel stack.

Four cases needed checking beyond the URL field. `krusader` (Utilities),
`krita` (Graphics) and `calligra` (Office) all have apps.kde.org pages despite
non-KDE upstream URLs — they stay. `keditbookmarks` has **no** apps.kde.org
page but ships in the `kde-applications` group; kept on the group test, as a
Konqueror-era utility that simply has no showcase page.

Going forward the rule is mechanical: a package belongs in `apps_list` iff its
pacman `Groups` contains `kde-applications`. `plasma` and `kf5` groups go to
the shell section; anything else isn't KDE and belongs in a host profile.

---

## Open defect

**R22 The guided menu offers invalid programs in both program pickers.**
Not caused by this refactor — pre-existing, found while pinning down the
System Program definition. Belongs with the guided-surface work (ADR 0058).

`_ctl_program_names` (`lib/guided-controller.sh:357`) enumerates every
`programs/<cat>/<name>/` with **no filter on the `system` flag**, and the same
unfiltered list feeds two pickers with opposite requirements:

| call site | field | needs | offered | invalid |
|-----------|-------|-------|---------|---------|
| line 369 | host `system_programs` | `system: true`  | all 15 | **12** |
| line 538 | User Editor `programs` | `system: false` | all 15 | **3**  |

Only `grub`, `cups` and `sops` are `system: true`.

Consequences differ per side:

- **Host.** `validate_programs "true" …` (`lib/config/validation.sh:97`)
  rejects a `system: false` entry, so picking `docker` or `borg` in the system
  programs row builds a Config State that fails validation at Proceed — after
  the operator has done all their other work.
- **User.** `validate_user_program` (`lib/config/layers.sh:150-172`) is more
  forgiving: referencing a System Program the host already installs is a no-op,
  otherwise it aborts. So picking `cups` for a user silently does nothing when
  the host has it, and aborts when it doesn't.

The function's own docstring already says "resolvable **System Program**
names", so the user-side call site was always a misuse.

Fix: split it in two — `_ctl_system_program_names` and
`_ctl_user_program_names`, each filtering on the `system` flag from the
program's `config.jsonc`, wired to line 369 and line 538 respectively. Worth
folding the flag into `configs_build_registry` (`lib/config/layers.sh:66`),
which already indexes name → `cat/name`, so a menu render doesn't re-parse 15
JSONC files.

Test: the `[x]`/`[ ]` option-set assertions for both pickers should assert the
*membership* of the list, not just the marking — that's what would have caught
this.
