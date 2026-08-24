# Promote config-hungry packages to Programs

A repo package that needs persistent machine/user state beyond its payload
(writing under `/etc`, enabling a service/timer, seeding config, patching
`makepkg.conf`) is promoted from a bare `packages.repo` entry to a Program
under `programs/<category>/<name>/`. The Program's `install.sh` owns **both**
the package install and its setup — the package leaves `packages.repo`, giving
it a single home (the same boundary ADR 0079 drew for `cups`). Packages that
install and work with no further state stay bare in `packages.repo`.

This is recorded because the change is hard to reverse (splitting a package's
install and config across two homes later is churn) and surprising without
context: a reader diffing `hosts/core/profile.jsonc` will wonder why `ccache`,
`reflector`, and `smartmontools` vanished from the package list.
