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
    -- rest.nvim pretty-prints responses via each ft's formatprg ('gq').
    local prg = {
      json = "jq",
      html = "prettier --parser html",
      xml = "xmllint --format -",
    }
    vim.api.nvim_create_autocmd("FileType", {
      pattern = vim.tbl_keys(prg),
      callback = function(ev) vim.bo[ev.buf].formatprg = prg[ev.match] end,
    })
  end,
}
