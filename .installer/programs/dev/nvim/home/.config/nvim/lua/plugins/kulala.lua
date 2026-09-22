-- kulala.nvim: run HTTP requests from .http/.rest files inside the editor, next
-- to the code that calls them. Pure Lua, no external deps; lazy-loads on the
-- http filetype. Maps under the <leader>R (REST) group.
return {
  "mistweaverco/kulala.nvim",
  ft = { "http", "rest" },
  keys = {
    {
      "<leader>Rs",
      function() require("kulala").run() end,
      desc = "REST: send request",
    },
    {
      "<leader>Ra",
      function() require("kulala").run_all() end,
      desc = "REST: send all",
    },
    {
      "<leader>Rn",
      function() require("kulala").jump_next() end,
      desc = "REST: next request",
    },
    {
      "<leader>Rp",
      function() require("kulala").jump_prev() end,
      desc = "REST: prev request",
    },
    {
      "<leader>Ri",
      function() require("kulala").inspect() end,
      desc = "REST: inspect",
    },
    {
      "<leader>Rc",
      function() require("kulala").copy() end,
      desc = "REST: copy as curl",
    },
  },
  init = function()
    -- Teach Neovim the .http/.rest extensions so the ft trigger fires.
    vim.filetype.add({ extension = { http = "http", rest = "rest" } })
  end,
  opts = {},
}
