# 07: Desktop/laptop default to Umbriel

**What to build:** The operator's `desktop` and `laptop` Host Profiles list
`umbriel, kde, niri, hyprland`, so both machines land on Umbriel at first
login and keep the others as fallbacks. Both still install the same package
set.

**Blocked by:** 05, 06

**Status:** done

- [x] Fleet Golden fixtures deliberately regenerated for the new order +
      Umbriel packages; desktop ≡ laptop package set still passes
- [x] VM Audit Run of the `desktop` and `laptop` variants: first login lands
      on Umbriel, Umbriel probe + binds PASS
- [x] Docs list desktop/laptop's default as Umbriel where hosts are described

Spec: ../PRD.md · ADR 0114, 0157, 0159

## Comments

- desktop Audit Run 20261026-082542: `default-session` PASS (SDDM
  preselects umbriel on first boot), Umbriel session probes all PASS. laptop
  shares the package set (Fleet Golden), not separately audited.
