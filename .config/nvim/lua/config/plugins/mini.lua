return {
	-- NOTE: mini.ai — better text objects (replaces nvim-treesitter-textobjects for most cases)
	{
		"echasnovski/mini.ai",
		version = false,
		event = "VeryLazy",
		dependencies = {
			{
				"echasnovski/mini.extra",
				version = false,
			},
		},
		config = function()
			require("mini.ai").setup({
				mappings = {
					around = "a",
					inside = "i",
				},
				custom_textobjects = {
					e = require("mini.extra").gen_ai_spec.buffer(),
				},
			})
		end,
	},

	-- NOTE: mini.files — file explorer
	{
		"echasnovski/mini.files",
		keys = {
			{
				"<leader>ee",
				function()
					require("mini.files").open()
				end,
				desc = "Open file explorer",
			},
			{
				"<leader>ef",
				function()
					require("mini.files").open(vim.api.nvim_buf_get_name(0), false)
				end,
				desc = "Open explorer at current file",
			},
			{
				"<leader>ecd",
				function()
					require("mini.files").open(vim.fn.getcwd())
				end,
				desc = "Open explorer at cwd",
			},
		},
		opts = {
			windows = {
				preview = true, -- show file preview on the right
				width_focus = 40,
				width_preview = 60,
			},
			options = {
				use_as_default_explorer = true, -- replaces netrw
			},
			mappings = {
				go_in = "<CR>",
				go_in_plus = "L",
				go_out = "-",
				go_out_plus = "H",
				-- reveal in system file manager
				reset = "<BS>",
				show_help = "g?",
				synchronize = "=",
			},
		},
		config = function(_, opts)
			require("mini.files").setup(opts)

			-- NOTE: show/hide dotfiles toggle
			local show_dotfiles = true
			local filter_dotfiles = function(fs_entry)
				return not vim.startswith(fs_entry.name, ".")
			end

			vim.api.nvim_create_autocmd("User", {
				pattern = "MiniFilesBufferCreate",
				callback = function(args)
					vim.keymap.set("n", "g.", function()
						show_dotfiles = not show_dotfiles
						require("mini.files").refresh({
							content = { filter = show_dotfiles and nil or filter_dotfiles },
						})
					end, { buffer = args.data.buf_id, desc = "Toggle dotfiles" })

					-- NOTE: open in split/vsplit from mini.files
					local map_split = function(buf_id, lhs, direction)
						vim.keymap.set("n", lhs, function()
							local entry = require("mini.files").get_fs_entry()
							if entry and entry.fs_type == "file" then
								require("mini.files").close()
								vim.cmd(direction .. " " .. vim.fn.fnameescape(entry.path))
							end
						end, { buffer = buf_id, desc = "Open in " .. direction })
					end

					map_split(args.data.buf_id, "<C-s>", "split")
					map_split(args.data.buf_id, "<C-v>", "vsplit")
				end,
			})
		end,
	},

	-- NOTE: mini.surround
	{
		"echasnovski/mini.surround",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			highlight_duration = 300,
			mappings = {
				add = "sa",
				delete = "ds",
				find = "sf",
				find_left = "sF",
				highlight = "sh",
				replace = "ca",
				update_n_lines = "sn",
				suffix_last = "l",
				suffix_next = "n",
			},
			n_lines = 20,
			search_method = "cover",
		},
	},

	-- NOTE: mini.trailspace
	{
		"echasnovski/mini.trailspace",
		event = { "BufReadPost", "BufNewFile" },
		opts = { only_in_normal_buffers = true },
		config = function(_, opts)
			local trailspace = require("mini.trailspace")
			trailspace.setup(opts)

			vim.keymap.set("n", "<leader>cw", function()
				trailspace.trim()
				trailspace.trim_last_lines() -- new: also trim trailing empty lines
				vim.notify("Whitespace trimmed", vim.log.levels.INFO)
			end, { desc = "Trim whitespace" })

			-- Unhighlight on move so it doesn't distract while typing
			vim.api.nvim_create_autocmd("CursorMoved", {
				callback = function()
					trailspace.unhighlight()
				end,
			})
		end,
	},

	-- NOTE: mini.splitjoin
	{
		"echasnovski/mini.splitjoin",
		keys = {
			{
				"sj",
				function()
					require("mini.splitjoin").join()
				end,
				mode = { "n", "x" },
				desc = "Join arguments",
			},
			{
				"sk",
				function()
					require("mini.splitjoin").split()
				end,
				mode = { "n", "x" },
				desc = "Split arguments",
			},
		},
		opts = {
			mappings = { toggle = "" }, -- disable default gS mapping
		},
	},

	-- NOTE: mini.pairs — auto pairs (replaces nvim-autopairs)
	{
		"echasnovski/mini.pairs",
		event = "InsertEnter",
		opts = {
			modes = { insert = true, command = true, terminal = false },
			skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
			skip_ts = { "string" },
			skip_unbalanced = true,
			markdown = true,
		},
	},

	-- NOTE: mini.icons — modern icon provider (replaces nvim-web-devicons)
	{
		"echasnovski/mini.icons",
		lazy = true,
		opts = {
			file = {
				[".keep"] = { glyph = "󰊢", hl = "MiniIconsGrey" },
				["devcontainer.json"] = { glyph = "", hl = "MiniIconsAzure" },
			},
			filetype = {
				dotenv = { glyph = "", hl = "MiniIconsYellow" },
			},
		},
		init = function()
			package.preload["nvim-web-devicons"] = function()
				require("mini.icons").mock_nvim_web_devicons()
				return package.loaded["nvim-web-devicons"]
			end
		end,
	},
}
