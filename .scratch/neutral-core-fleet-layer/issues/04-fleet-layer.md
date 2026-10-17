# 04: Fleet Layer

**What to build:** the operator's personal software stops being everyone's
default. A Fleet Layer, folded Host Core → Fleet Layer → host by `desktop` and
`laptop` only, takes Host Core's whole Host Package List and base Host Programs;
Host Core keeps only `vm.swappiness`. It is a layer, not a machine: hidden
from the Profiles picker and rejected by `install.sh --profile`. The Guided
pick (ticket 03) folds it exactly as `--profile` does. See PRD and
[[ADR 0157]].

**Blocked by:** 02 (Golden capture), 03 (Guided profile pick re-baselines)

**Status:** done

- [x] Golden test (02) passes unchanged for `desktop` and `laptop`
- [x] `minimal`, `*-pure` and VM fixtures resolve with no Fleet Layer content
- [x] Profiles picker does not list `fleet`; `--profile fleet` aborts clearly
- [x] Guided pick ≡ `--profile` (03's test) still green for every profile
- [x] CONTEXT.md Host Core entry and profile header comments updated
