return {
	{
		"folke/snacks.nvim",
		priority = 1000,
		lazy = false,
		---@type snacks.Config
		opts = {
			bigfile = { enabled = true },
			indent = { enabled = true },
			notifier = { enabled = true, timeout = 3000 },
			scope = { enabled = true },
			scroll = { enabled = true },
			statuscolumn = { enabled = true },
			words = { enabled = true },
			explorer = { enabled = true },
			input = { enabled = true },

			quickfile = {
				enabled = true,
				exclude = { "latex" },
			},

			styles = {
				input = {
					keys = {
						n_esc = { "<C-c>", { "cmp_close", "cancel" }, mode = "n", expr = true },
						i_esc = { "<C-c>", { "cmp_close", "stopinsert" }, mode = "i", expr = true },
					},
				},
			},

			image = {
				enabled = function()
					return vim.bo.filetype == "markdown"
				end,
				doc = {
					float = false,
					inline = false,
					max_width = 50,
					max_height = 30,
					wo = { wrap = false },
				},
				convert = { notify = false, command = "magick" },
				img_dirs = {
					"img",
					"images",
					"assets",
					"static",
					"public",
					"media",
					"attachments",
					"~/Downloads",
				},
			},

			dashboard = {
				enabled = true,
				sections = {
					{ section = "header" },
					{ section = "keys", gap = 1, padding = 1 },
					{ section = "startup" },
				},
			},

			picker = {
				enabled = true,
				ui_select = true, -- replaces vim.ui.select (no telescope-ui-select needed)
				matchers = { frecency = true, cwd_bonus = false },
				exclude = { ".git", "node_modules", "dist", "build" },
				formatters = {
					file = {
						filename_first = true,
						filename_only = false,
						icon_width = 2,
					},
				},
				layout = { preset = "telescope", cycle = false },
				win = {
					input = {
						keys = {
							-- NOTE: consistent with your blink/noice escape
							["<C-c>"] = { "close", mode = { "n", "i" } },
						},
					},
				},
				layouts = {
					select = {
						preview = false,
						layout = {
							backdrop = false,
							width = 0.6,
							min_width = 80,
							height = 0.4,
							min_height = 10,
							box = "vertical",
							border = "rounded",
							title = "{title}",
							title_pos = "center",
							{ win = "input", height = 1, border = "bottom" },
							{ win = "list", border = "none" },
							{ win = "preview", title = "{preview}", width = 0.6, height = 0.4, border = "top" },
						},
					},
					telescope = {
						reverse = true,
						layout = {
							box = "horizontal",
							backdrop = false,
							width = 0.8,
							height = 0.9,
							border = "none",
							{
								box = "vertical",
								{ win = "list", title = " Results ", title_pos = "center", border = "rounded" },
								{
									win = "input",
									height = 1,
									border = "rounded",
									title = "{title} {live} {flags}",
									title_pos = "center",
								},
							},
							{
								win = "preview",
								title = "{preview:Preview}",
								width = 0.50,
								border = "rounded",
								title_pos = "center",
							},
						},
					},
					ivy = {
						layout = {
							box = "vertical",
							backdrop = false,
							width = 0,
							height = 0.4,
							position = "bottom",
							border = "top",
							title = " {title} {live} {flags}",
							title_pos = "left",
							{ win = "input", height = 1, border = "bottom" },
							{
								box = "horizontal",
								{ win = "list", border = "none" },
								{ win = "preview", title = "{preview}", width = 0.5, border = "left" },
							},
						},
					},
				},
			},
		},

		keys = {
			-- ============================================================
			-- NOTE: Git
			-- ============================================================
			{
				"<leader>lg",
				function()
					Snacks.lazygit()
				end,
				desc = "Lazygit",
			},
			{
				"<leader>gl",
				function()
					Snacks.lazygit.log()
				end,
				desc = "Lazygit Logs",
			},
			{
				"<leader>gB",
				function()
					Snacks.gitbrowse()
				end,
				desc = "Git Browse",
			},
			{
				"<leader>gbl",
				function()
					Snacks.git.blame_line()
				end,
				desc = "Git Blame Line",
			},
			{
				"<leader>gbr",
				function()
					Snacks.picker.git_branches({ layout = "select" })
				end,
				desc = "Git Branches",
			},
			{
				"<leader>gL",
				function()
					Snacks.picker.git_log()
				end,
				desc = "Git Log",
			},
			{
				"<leader>gS",
				function()
					Snacks.picker.git_status()
				end,
				desc = "Git Status",
			},

			-- ============================================================
			-- NOTE: Files / Buffers
			-- ============================================================
			{
				"<leader>rN",
				function()
					Snacks.rename.rename_file()
				end,
				desc = "Rename File",
			},
			{
				"<leader>bd",
				function()
					Snacks.bufdelete()
				end,
				desc = "Delete Buffer",
			},
			{
				"<leader>e",
				function()
					Snacks.explorer()
				end,
				desc = "File Explorer",
			},

			-- ============================================================
			-- NOTE: Picker
			-- ============================================================
			{
				"<leader>pf",
				function()
					Snacks.picker.files()
				end,
				desc = "Find Files",
			},
			{
				"<leader>ps",
				function()
					Snacks.picker.grep()
				end,
				desc = "Grep",
			},
			{
				"<leader>pb",
				function()
					Snacks.picker.buffers()
				end,
				desc = "Buffers",
			},
			{
				"<leader>pr",
				function()
					Snacks.picker.recent()
				end,
				desc = "Recent Files",
			},
			{
				"<leader>pd",
				function()
					Snacks.picker.diagnostics()
				end,
				desc = "Diagnostics",
			},
			{
				"<leader>p/",
				function()
					Snacks.picker.grep_buffers()
				end,
				desc = "Grep Open Buffers",
			},
			{
				"<leader>pc",
				function()
					Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
				end,
				desc = "Config Files",
			},
			{
				"<leader>pu",
				function()
					Snacks.picker.undo()
				end,
				desc = "Undo History",
			},
			{
				"<leader>pk",
				function()
					Snacks.picker.keymaps({ layout = "ivy" })
				end,
				desc = "Keymaps",
			},
			{
				"<leader>vh",
				function()
					Snacks.picker.help()
				end,
				desc = "Help Pages",
			},
			{
				"<leader>pws",
				function()
					Snacks.picker.grep_word()
				end,
				desc = "Grep Word/Selection",
				mode = { "n", "x" },
			},
			-- NOTE: replaces telescope current_buffer_fuzzy_find
			{
				"<leader>/",
				function()
					Snacks.picker.lines()
				end,
				desc = "Search current buffer",
			},

			-- ============================================================
			-- NOTE: Colorscheme — persists selection to colorscheme.lua
			-- ============================================================
			{
				"<leader>th",
				function()
					Snacks.picker.colorschemes({
						layout = "ivy",
						confirm = function(picker, item)
							if item then
								-- nil out the preview state so snacks doesn't revert on close
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

			-- ============================================================
			-- NOTE: Notifications
			-- ============================================================
			{
				"<leader>n",
				function()
					Snacks.picker.notifications()
				end,
				desc = "Notification History",
			},
			{
				"<leader>un",
				function()
					Snacks.notifier.hide()
				end,
				desc = "Dismiss Notifications",
			},

			-- ============================================================
			-- NOTE: Words
			-- ============================================================
			{
				"]]",
				function()
					Snacks.words.jump(vim.v.count1)
				end,
				desc = "Next Word Reference",
			},
			{
				"[[",
				function()
					Snacks.words.jump(-vim.v.count1)
				end,
				desc = "Prev Word Reference",
			},

			-- ============================================================
			-- NOTE: Zen
			-- ============================================================
			{
				"<leader>z",
				function()
					Snacks.zen()
				end,
				desc = "Zen Mode",
			},
			{
				"<leader>Z",
				function()
					Snacks.zoom()
				end,
				desc = "Zoom Mode",
			},
		},
	},

	-- NOTE: todo-comments
	{
		"folke/todo-comments.nvim",
		event = { "BufReadPre", "BufNewFile" },
		optional = true,
		keys = {
			{
				"<leader>pt",
				function()
					Snacks.picker.todo_comments()
				end,
				desc = "Todo Comments (All)",
			},
			{
				"<leader>pT",
				function()
					Snacks.picker.todo_comments({ keywords = { "TODO", "FORGETNOT", "FIXME" } })
				end,
				desc = "Todo Comments (Main)",
			},
		},
	},
}
