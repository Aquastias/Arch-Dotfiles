-- LSP (ADR 0135). nvim-lspconfig ships the server configs; we turn them on with
-- native vim.lsp.enable (0.11+). Every server installs as a system package
-- (Host Core language-servers) — no mason. ts_ls covers js/ts/jsx/tsx and
-- solid; html/cssls/jsonls/eslint come from vscode-langservers-extracted.
-- Swift (sourcekit) is best-effort — enabled only when its binary is present.
return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      { "j-hui/fidget.nvim", opts = {} },
      {
        "folke/lazydev.nvim",
        ft = "lua",
        opts = {
          library = {
            { path = "${3rd}/luv/library", words = { "vim%.uv" } },
          },
        },
      },
    },
    config = function()
      vim.diagnostic.config({
        severity_sort = true,
        float = { border = "rounded", source = true },
        virtual_text = { spacing = 2 },
        signs = true,
      })

      -- Per-buffer keymaps once a server attaches.
      local grp = vim.api.nvim_create_augroup("nvim-lsp", { clear = true })
      vim.api.nvim_create_autocmd("LspAttach", {
        group = grp,
        callback = function(ev)
          local map = function(keys, fn, desc)
            vim.keymap.set(
              "n",
              keys,
              fn,
              { buffer = ev.buf, desc = "LSP: " .. desc }
            )
          end
          map("grn", vim.lsp.buf.rename, "Rename")
          map("gra", vim.lsp.buf.code_action, "Code action")
          map("grr", vim.lsp.buf.references, "References")
          map("gri", vim.lsp.buf.implementation, "Implementation")
          map("grd", vim.lsp.buf.definition, "Definition")
          map("K", vim.lsp.buf.hover, "Hover")
        end,
      })

      -- Advertise blink.cmp's completion capabilities to every server.
      local caps = vim.lsp.protocol.make_client_capabilities()
      local ok, blink = pcall(require, "blink.cmp")
      if ok then
        caps = blink.get_lsp_capabilities(caps)
      end
      vim.lsp.config("*", { capabilities = caps })

      vim.lsp.enable({
        "lua_ls",
        "basedpyright",
        "nixd",
        "phpactor",
        "svelte",
        "vue_ls",
        "tailwindcss",
        "emmet_language_server",
        "ts_ls",
        "html",
        "cssls",
        "jsonls",
        "eslint",
        "yamlls",
        "bashls",
        "gopls",
        "rust_analyzer",
        "zls",
        "clangd",
      })

      -- Swift is best-effort: enable sourcekit only when its binary exists.
      if vim.fn.executable("sourcekit-lsp") == 1 then
        vim.lsp.enable("sourcekit")
      end
    end,
  },
}
