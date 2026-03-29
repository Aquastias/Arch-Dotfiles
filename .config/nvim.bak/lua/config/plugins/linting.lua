return {
	"mfussenegger/nvim-lint",
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		linters_by_ft = {
			javascript = { "biomejs" },
			typescript = { "biomejs" },
			javascriptreact = { "biomejs" },
			typescriptreact = { "biomejs" },
			svelte = { "biomejs" },
			python = { "pylint" },
		},
	},
	config = function(_, opts)
		local lint = require("lint")

		lint.linters_by_ft = opts.linters_by_ft

		-- Only run biome if biome.json exists in the project
		lint.linters.biomejs = vim.tbl_deep_extend("force", lint.linters.biomejs or {}, {
			condition = function(ctx)
				return vim.fs.find({ "biome.json", "biome.jsonc" }, { path = ctx.filename, upward = true })[1] ~= nil
			end,
		})

		vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave", "BufEnter" }, {
			group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
			callback = function()
				-- only lint if the buffer has a real file
				if vim.bo.buftype == "" then
					lint.try_lint()
				end
			end,
		})

		vim.keymap.set("n", "<leader>L", function()
			lint.try_lint()
			vim.notify("Linting " .. vim.fn.expand("%:t"), vim.log.levels.INFO)
		end, { desc = "Trigger linting for current file" })
	end,
}
