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
          map("<leader>co", function()
            vim.lsp.buf.code_action({
              context = { only = { "source.organizeImports" } },
              apply = true,
            })
          end, "Organize imports")

          -- Inlay hints on by default where the server supports them; the
          -- <leader>uh toggle (keymaps.lua) silences them per buffer.
          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          if client and client:supports_method("textDocument/inlayHint") then
            vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
          end
        end,
      })

      -- Advertise blink.cmp's completion capabilities to every server.
      local caps = vim.lsp.protocol.make_client_capabilities()
      local ok, blink = pcall(require, "blink.cmp")
      if ok then
        caps = blink.get_lsp_capabilities(caps)
      end
      -- Advertise folding ranges so nvim-ufo's LSP provider works (ufo.lua).
      caps.textDocument = caps.textDocument or {}
      caps.textDocument.foldingRange =
        { dynamicRegistration = false, lineFoldingOnly = true }
      vim.lsp.config("*", { capabilities = caps })

      -- Server list comes from the Language Registry (ADR 0141), de-duped.
      vim.lsp.enable(require("config.languages").servers())

      -- Swift is best-effort: enable sourcekit only when its binary exists.
      if vim.fn.executable("sourcekit-lsp") == 1 then
        vim.lsp.enable("sourcekit")
      end
    end,
  },
}
