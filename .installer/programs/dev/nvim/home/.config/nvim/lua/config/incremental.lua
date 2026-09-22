-- Incremental selection by treesitter node (WebStorm Ctrl+W), no plugin.
-- expand() selects the node under the cursor, then grows to the parent on each
-- call; shrink() pops back down the stack. Charwise, inclusive selection.
local M = {}
local stack = {}

local function same_range(a, b)
  local a1, a2, a3, a4 = a:range()
  local b1, b2, b3, b4 = b:range()
  return a1 == b1 and a2 == b2 and a3 == b3 and a4 == b4
end

local function select(node)
  local srow, scol, erow, ecol = node:range()
  -- Treesitter end is exclusive; convert to an inclusive charwise selection.
  if ecol == 0 then
    erow = erow - 1
    ecol = #(vim.api.nvim_buf_get_lines(0, erow, erow + 1, false)[1] or "")
  end
  vim.api.nvim_win_set_cursor(0, { srow + 1, scol })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { erow + 1, math.max(ecol - 1, 0) })
end

function M.expand()
  if #stack == 0 then
    local node = vim.treesitter.get_node()
    if not node then
      return
    end
    stack = { node }
    return select(node)
  end
  local cur = stack[#stack]
  local parent = cur:parent()
  while parent and same_range(parent, cur) do
    parent = parent:parent()
  end
  if parent then
    stack[#stack + 1] = parent
    select(parent)
  else
    select(cur)
  end
end

function M.shrink()
  if #stack > 1 then
    table.remove(stack)
  end
  local cur = stack[#stack]
  if cur then
    select(cur)
  end
end

return M
