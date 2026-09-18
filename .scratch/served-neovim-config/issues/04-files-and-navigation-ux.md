# 04: Files & navigation UX

**What to build:** The file/navigation surface: snacks (picker, dashboard,
notifier), oil (buffer-as-directory), neo-tree (sidebar), and harpoon. These
reproduce prototype screens 1 (dashboard), 5 (oil), 6 (neo-tree), 7 (picker),
9 (harpoon).

**Blocked by:** 01.

**Status:** ready-for-agent

- [ ] snacks.picker does files + live grep with a preview pane (screen 7).
- [ ] snacks.dashboard is the start screen (screen 1); snacks.notifier shows
      toasts (screen 13's toast).
- [ ] oil opens the parent directory as an editable buffer (screen 5).
- [ ] neo-tree sidebar shows the tree with git status + diagnostics (screen 6).
- [ ] harpoon add + quick-menu navigation works (screen 9).
- [ ] All surfaces are accent-aware (sapphire) and match the prototype layout.
