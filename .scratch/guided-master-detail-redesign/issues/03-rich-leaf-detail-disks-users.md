# 03 — Rich leaf detail: reuse Disks pool tree + Users account table

**What to build:** The two leaves that carry more than a scalar render their
existing rich views inside the always-on detail pane. At the Disks `pools` leaf
the pane shows the current ZFS pool / topology tree; at the Users leaf it shows
the account table (name, shell, sudo, groups). Both reuse the builders that
already produce these views elsewhere in the controller — no new render is
invented.

**Blocked by:** 02 — extends the always-on pane's leaf dispatch to route these
two leaves to their rich builders.

**Status:** ready-for-agent

- [ ] The Disks `pools` leaf previews the ZFS pool/topology tree via the existing
      layout-graph builder.
- [ ] The Users leaf previews the account table (name, shell, sudo, groups) via
      the existing user-panel builder.
- [ ] Both reuse current builders — no duplicate render logic added.
- [ ] The parent column still renders above each rich leaf detail.
- [ ] The headless bats suite asserts the pool tree and the account table appear
      at their leaves — and passes.
