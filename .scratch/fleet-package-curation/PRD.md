# PRD: Fleet package curation (retroactive)

Status: done

Retroactive record — ad-hoc package moves shipped without a grill session.
Anchored by [[ADR 0114]] (fleet software in core; laptop is a superset) and
[[ADR 0056]].

## What shipped

- Minimal desktop-less base profile (`hosts/minimal`).
- Dev toolchain + gamemode promoted to Host Core; gamemode a host program.
- Added to core: Kate language servers, mpv (ani-cli), obs-studio, Discord
  (favorited in KDE), `rar` (replacing `unrar`, for `mktarrar`).
- Dropped from desktop AUR list: brave-bin, ckb-next-git.

## Commits

fef764a, 6ef6b9b, 6041783, 6af9f0e, 25ae1a5, 856d446, 3918ff4, 00637b5,
7ee5113, 1f98879, a603999.
