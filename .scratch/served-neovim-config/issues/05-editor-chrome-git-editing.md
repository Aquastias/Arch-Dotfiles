# 05: Editor chrome, git & editing helpers

**What to build:** The statusline/bufferline chrome, git integration, and
editing helpers: lualine, bufferline, which-key, mini.ai, mini.pairs, nvim-ufo,
render-markdown, todo-comments, undotree, gitsigns, fugitive, nvim-emmet. These
reproduce prototype screens 2 (editing/statusline/bufferline/gitsigns/fold),
8 (which-key), 10 (fugitive + inline blame), 11 (undotree), 12 (render-markdown).

**Blocked by:** 01.

**Status:** done

- [x] lualine statusline + bufferline tabs are accent-aware and match screen 2.
- [x] gitsigns shows add/change/delete signs + inline blame; fugitive runs raw
      git and shows the status buffer (screen 10).
- [x] which-key shows the leader popup (screen 8); nvim-ufo folding works
      (foldcolumn in screen 2).
- [x] mini.ai text objects + mini.pairs autopairs work.
- [x] render-markdown renders headings/code/checkboxes in-buffer (screen 12);
      undotree shows history + diff (screen 11); todo-comments highlights +
      jumps; nvim-emmet wraps/expands abbreviations.
