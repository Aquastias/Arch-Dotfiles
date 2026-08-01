# Exclusivity validation replaces promotion

Status: done

## Parent

.scratch/layered-software-model/PRD.md (R9, R12)

## What to build

The same config file currently installs differently depending on which
front-end reads it. The rule that promotes a package entry naming a Program
into `system_programs` runs only in the Guided Installer's emit path;
`install.sh --profile` and `install.sh <config-file>` never promote. A
hand-edited profile and a TUI-authored one are not equivalent, which breaks the
requirement that configurations work when manually edited.

Fix it by making a name mean one thing. A name is **either** a Program **or** a
package, never both. Any `packages.repo` or `packages.aur` entry that resolves
to a program directory aborts at config load, naming the offending path and the
correct slot to use instead. With that in place, promotion has nothing left to
do — delete it.

To keep the guided convenience without the divergence, the extra-packages row
resolves what the operator types **at entry time**: typing a Program name tells
them so and routes it to the right slot before anything is stored. What lands
in Config State is always canonical, so Save, Export and Proceed all agree.

Three live violations must be removed for the committed profiles to still load:
`docker` and `virt-manager` are declared as repo packages on both hosts while
also being user Programs, and `teamspeak3` is declared as a repo package on
`desktop` despite being AUR-only — its Program installs it with the AUR helper,
so pacstrap would fail on it today. `docker-compose` is not a Program and folds
into the docker Program's install script rather than being stranded.

## Acceptance criteria

- [ ] A `packages.repo` entry resolving to a `system: true` Program aborts at load
- [ ] A `packages.repo` entry resolving to a `system: false` Program aborts at load
- [ ] The same applies to `packages.aur` entries
- [ ] The abort message names the offending path and the correct slot
- [ ] A plain package name that matches no program directory passes
- [ ] An empty or absent package list passes
- [ ] Promotion is deleted, along with its tests
- [ ] All three front-ends produce an identical Effective Config from an
      identical profile
- [ ] Typing a Program name in the guided extra-packages row reports it and
      routes it to the correct slot before storing
- [ ] `docker`, `virt-manager` and `teamspeak3` are removed from both hosts'
      `packages.repo`
- [ ] `docker-compose` is installed by the docker Program
- [ ] `desktop` and `laptop` still load and resolve

## Blocked by

- Program kind is authoritative
- Collapse the package slots
