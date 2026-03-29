return {
  "folke/snacks.nvim",
  keys = {
    {
      "<leader>uC",
      function()
        Snacks.picker.colorschemes({
          layout = "ivy",
          confirm = function(picker, item)
            if item then
              picker.preview.state.colorscheme = nil
              picker:close()
              vim.schedule(function()
                vim.cmd.colorscheme(item.text)
                local path = vim.fn.stdpath("config") .. "/lua/colorscheme.lua"
                local file = io.open(path, "w")
                if file then
                  file:write('vim.cmd.colorscheme("' .. item.text .. '")\n')
                  file:close()
                  vim.notify("Theme saved: " .. item.text, vim.log.levels.INFO)
                end
              end)
            end
          end,
        })
      end,
      desc = "Pick and save colorscheme",
    },
  },
}
