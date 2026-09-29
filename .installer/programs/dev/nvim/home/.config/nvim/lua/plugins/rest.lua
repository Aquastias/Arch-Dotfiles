-- rest.nvim: run HTTP requests from .http/.rest files inside the editor, next
-- to the code that calls them. Replaces kulala.nvim (upstream went private).
-- Deps come as luarocks rocks via lazy (system luarocks, ADR 0150); lazy-loads
-- on the http filetype. Maps under the <leader>R (REST) group.
return {
  "rest-nvim/rest.nvim",
  ft = "http",
  keys = {
    { "<leader>Rs", "<cmd>Rest run<cr>", desc = "REST: send request" },
    { "<leader>Rl", "<cmd>Rest last<cr>", desc = "REST: resend last" },
    { "<leader>Ro", "<cmd>Rest open<cr>", desc = "REST: open result" },
    { "<leader>Re", "<cmd>Rest env select<cr>", desc = "REST: select env" },
    { "<leader>Rc", "<cmd>Rest curl yank<cr>", desc = "REST: copy as curl" },
  },
  init = function()
    -- rest.nvim only runs on the http ft; fold .rest files into it.
    vim.filetype.add({ extension = { http = "http", rest = "http" } })
  end,
}
