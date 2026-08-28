# My Arch Linux dotfiles

This directory contains the dotfiles for my Arch Linux system: Eterniox.

## OS Installer

A fully scripted, config-driven Arch Linux installer with ZFS lives in [`.installer/`](.installer/). It handles partitioning, ZFS pool creation, chroot configuration, desktop environments, and optional VM testing.

See [`.installer/README.md`](.installer/README.md) for setup, configuration reference, and VM testing.

---

## Requirements

Ensure you have the following installed on your system:

### Git

```bash
pacman -S git
```

### Stow

```bash
pacman -S stow
```

> To provision a whole machine (partitioning, filesystem, desktop, users,
> secrets) rather than just symlink dotfiles, use the installer in
> [`.installer/`](.installer/) — see [`.installer/README.md`](.installer/README.md). The package
> manifests it manages live under `.installer/hosts/<name>/` (`pkglist-repo.txt`
> / `pkglist-aur.txt`, written by `.installer/tools/save-pkglist.sh`).

## Installation

First, check out the dotfiles repo in your $HOME directory using git

```bash
$ git clone git@github.com:Aquastias/Arch-Dotfiles.git .dotfiles
$ cd .dotfiles
```

then use GNU stow to create symlinks

```bash
$ stow .
```

