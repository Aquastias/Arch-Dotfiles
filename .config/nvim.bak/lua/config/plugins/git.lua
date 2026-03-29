return {
	-- NOTE: vim-fugitive — unchanged, still the best for raw git commands
	{
		"tpope/vim-fugitive",
		cmd = { "Git", "G" },
		config = function()
			vim.keymap.set("n", "<leader>gg", "<cmd>tabnew | Git | only<cr>", { desc = "Fugitive fullscreen tab" })

			vim.api.nvim_create_autocmd("BufWinEnter", {
				group = vim.api.nvim_create_augroup("myFugitive", { clear = true }),
				pattern = "*",
				callback = function()
					if vim.bo.ft ~= "fugitive" then
						return
					end
					local opts = { buffer = vim.api.nvim_get_current_buf(), remap = false }
					vim.keymap.set("n", "<leader>P", function()
						vim.cmd.Git("push")
					end, vim.tbl_extend("force", opts, { desc = "Git push" }))
					vim.keymap.set("n", "<leader>p", function()
						vim.cmd.Git({ "pull", "--rebase" })
					end, vim.tbl_extend("force", opts, { desc = "Git pull --rebase" }))
					vim.keymap.set(
						"n",
						"<leader>t",
						":Git push -u origin ",
						vim.tbl_extend("force", opts, { desc = "Git push -u origin" })
					)
				end,
			})
		end,
	},

	-- NOTE: gitsigns — updated to modern API
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			signs = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "" },
				topdelete = { text = "" },
				changedelete = { text = "▎" },
				untracked = { text = "▎" },
			},
			-- NOTE: new in modern gitsigns — shows staged signs separately
			signs_staged = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "" },
				topdelete = { text = "" },
				changedelete = { text = "▎" },
			},
			signs_staged_enable = true,
			attach_to_untracked = true,
			current_line_blame = false,
			current_line_blame_opts = {
				virt_text = true,
				virt_text_pos = "eol",
				delay = 500,
			},
			on_attach = function(bufnr)
				local gs = require("gitsigns")

				local function map(mode, l, r, desc)
					vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
				end

				-- NOTE: Navigation — respects vim diff mode
				map("n", "]h", function()
					if vim.wo.diff then
						vim.cmd.normal({ "]c", bang = true })
					else
						gs.nav_hunk("next") -- new API: nav_hunk replaces next_hunk/prev_hunk
					end
				end, "Next Hunk")

				map("n", "[h", function()
					if vim.wo.diff then
						vim.cmd.normal({ "[c", bang = true })
					else
						gs.nav_hunk("prev")
					end
				end, "Prev Hunk")

				map("n", "]H", function()
					gs.nav_hunk("last")
				end, "Last Hunk")
				map("n", "[H", function()
					gs.nav_hunk("first")
				end, "First Hunk")

				-- NOTE: Actions
				map({ "n", "v" }, "<leader>gs", "<cmd>Gitsigns stage_hunk<CR>", "Stage hunk")
				map({ "n", "v" }, "<leader>gr", "<cmd>Gitsigns reset_hunk<CR>", "Reset hunk")
				map("n", "<leader>gS", gs.stage_buffer, "Stage buffer")
				map("n", "<leader>gR", gs.reset_buffer, "Reset buffer")
				map("n", "<leader>gu", gs.undo_stage_hunk, "Undo stage hunk")
				map("n", "<leader>gp", gs.preview_hunk_inline, "Preview hunk inline") -- new: inline preview
				map("n", "<leader>gP", gs.preview_hunk, "Preview hunk popup")
				map("n", "<leader>gbl", function()
					gs.blame_line({ full = true })
				end, "Blame line")
				map("n", "<leader>gB", gs.toggle_current_line_blame, "Toggle line blame")
				map("n", "<leader>gd", gs.diffthis, "Diff this")
				map("n", "<leader>gD", function()
					gs.diffthis("~")
				end, "Diff this ~")
				map("n", "<leader>gq", "<cmd>Gitsigns setqflist<CR>", "Hunks to quickfix")

				-- NOTE: Text object
				map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "Select hunk")
			end,
		},
	},

	-- NOTE: lazygit.nvim — kept disabled since you use Snacks for this
	{
		"kdheepak/lazygit.nvim",
		enabled = false,
	},
}
