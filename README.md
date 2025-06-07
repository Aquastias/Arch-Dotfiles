# My Arch Linux dotfiles

This directory contains the dotfiles for my Arch Linux system: Eterniox.

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

Also you can have as a reference the packages mentioned in installed_packages.txt

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

