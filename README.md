# My Arch Linux dotfiles

This directory contains the dotfiles for my Arch Linux system: Eterniox.

## Requirements

Ensure you have the following installed on your system:

### Git

```
pacman -S git
```

### Stow

```
pacman -S stow
```

Also you can have as a reference the packages mentioned in installed_packages.txt

## Installation

First, check out the dotfiles repo in your $HOME directory using git

```
$ git clone git@github.com:Aquastias/Arch-Dotfiles.git
$ cd .dotfiles
```

then use GNU stow to create symlinks

```
$ stow .
```
