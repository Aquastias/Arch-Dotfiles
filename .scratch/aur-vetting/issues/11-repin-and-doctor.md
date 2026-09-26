# 11: repin + doctor

**What to build:** a legit maintainer transfer can be accepted, and a
paru.conf that drops the hook is caught.
- `sudo aur-vet repin <pkgbase>`: a fresh AUR clone, evaluated like the
  hook; shows old → new maintainer, the AUR's LastModified, all findings
  and the diff since the Vetted Commit (a full review if it's gone). You
  type the new maintainer's name (case-insensitive; AUR names are ASCII
  `[A-Za-z0-9._-]`, else the first 8 characters of the new commit). Clears
  only `trust-maintainer-changed`: any other critical, or an unreachable
  RPC, refuses. Interactive only.
- The hook keeps the maintainer change critical and names the command.
- `aur-vet doctor` warns when `$PARU_CONF`, the user's paru.conf or
  `/etc/paru.conf` lacks the hook; `/etc/profile.d/aur-vet.sh` runs it at
  every login. No per-user paru.conf ships.

**Blocked by:** 05, 06.

**Status:** done

- [x] Hook abort names `sudo aur-vet repin <pkgbase>`.
- [x] Typed name (any case) accepts; wrong name keeps the old pin.
- [x] Non-charset name falls back to the commit prefix.
- [x] Refuses unattended, unpinned, other criticals, RPC down.
- [x] doctor silent when hooked; warns for user conf, $PARU_CONF, /etc.
- [x] Login hook installed for every user.
