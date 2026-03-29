return {
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		dependencies = { "MunifTanjim/nui.nvim" },
		opts = {
			-- NOTE: cmdline enabled with popup view
			cmdline = {
				enabled = true,
				view = "cmdline_popup",
				format = {
					cmdline = { pattern = "^:", icon = "󱐌 :", lang = "vim" },
					help = { pattern = "^:%s*he?l?p?%s+", icon = " 󰮦 :" },
					search_down = { kind = "search", pattern = "^/", icon = "/", lang = "regex" },
					search_up = { kind = "search", pattern = "^%?", icon = "?", lang = "regex" },
					filter = { pattern = "^:%s*!", icon = " $ :", lang = "bash" },
					lua = {
						pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*", "^:%s*=%s*" },
						icon = "  :",
						lang = "lua",
					},
					input = { view = "cmdline_input", icon = " 󰥻 :" },
				},
			},

			messages = {
				enabled = true, -- needed for routing to work properly
			},

			-- NOTE: popupmenu backend changed from "cmp" to "nui" for blink.cmp compat
			popupmenu = {
				enabled = true,
				backend = "nui",
			},

			-- NOTE: presets — easier than manually configuring views
			presets = {
				bottom_search = false, -- keep search in popup, not bottom cmdline
				command_palette = true, -- positions cmdline + popupmenu together
				long_message_to_split = true, -- long output goes to a split, not a popup
				lsp_doc_border = true, -- border on hover/signature docs
			},

			views = {
				cmdline_popup = {
					position = { row = "40%", col = "50%" },
					size = { width = 60, height = "auto" },
					border = { style = "rounded" },
					win_options = {
						winhighlight = { Normal = "Normal", FloatBorder = "DiagnosticInfo" },
					},
				},
				popupmenu = {
					relative = "editor",
					position = { row = 8, col = "50%" },
					size = { width = 60, height = 10 },
					border = { style = "rounded" },
					win_options = {
						winhighlight = { Normal = "Normal", FloatBorder = "DiagnosticInfo" },
					},
				},
				mini = {
					win_options = { winblend = 0 },
					size = { width = "auto", height = "auto", max_height = 15 },
					position = { row = -2, col = "100%" },
				},
			},

			lsp = {
				progress = { enabled = true },
				hover = { enabled = true },
				signature = {
					enabled = true,
					auto_open = { enabled = false }, -- keep: don't auto-open on insert
				},
				-- NOTE: updated — removed cmp.entry.get_documentation (cmp is gone)
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
				},
				documentation = {
					auto_show = true,
					view = "hover",
				},
			},

			-- NOTE: routes — kept yours + added common noise filters
			routes = {
				-- skip common save/edit noise
				{
					filter = {
						event = "msg_show",
						any = {
							{ find = "%d+L, %d+B" },
							{ find = "; after #%d+" },
							{ find = "; before #%d+" },
							{ find = "%d fewer lines" },
							{ find = "%d more lines" },
							{ find = "written" }, -- "[file] written"
							{ find = "^%s*$" }, -- empty messages
						},
					},
					opts = { skip = true },
				},
				-- send long messages to split instead of popup
				{
					filter = { event = "msg_show", min_height = 10 },
					view = "split",
				},
				-- send search count to mini (bottom right, non-intrusive)
				{
					filter = { event = "msg_show", kind = "search_count" },
					opts = { skip = true },
				},
			},

			health = { checker = true },
		},

		keys = {
			{ "<leader>nol", "<cmd>Noice last<CR>", desc = "Noice Last" },
			{ "<leader>noh", "<cmd>Noice history<CR>", desc = "Noice History" },
			{ "<leader>nod", "<cmd>Noice dismiss<CR>", desc = "Noice Dismiss" },
			{ "<leader>noe", "<cmd>Noice errors<CR>", desc = "Noice Errors" },

			-- scroll in hover/signature docs
			{
				"<C-f>",
				function()
					if not require("noice.lsp").scroll(4) then
						return "<C-f>"
					end
				end,
				silent = true,
				expr = true,
				desc = "Scroll docs forward",
				mode = { "i", "n", "s" },
			},
			{
				"<C-b>",
				function()
					if not require("noice.lsp").scroll(-4) then
						return "<C-b>"
					end
				end,
				silent = true,
				expr = true,
				desc = "Scroll docs backward",
				mode = { "i", "n", "s" },
			},
		},
	},
}
