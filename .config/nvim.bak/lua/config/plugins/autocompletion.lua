return {
	"saghen/blink.cmp",
	event = "InsertEnter",
	version = "1.*",
	dependencies = {
		"rafamadriz/friendly-snippets",
		"ribru17/blink-cmp-spell",
		"onsails/lspkind.nvim",
	},
	opts_extend = { "sources.default" },
	opts = {
		-- Use pre-built binaries
		fuzzy = { implementation = "prefer_rust_with_warning" },

		appearance = {
			nerd_font_variant = "mono",
			use_nvim_cmp_as_default = false,
			kind_icons = {
				Class = " ",
				Color = " ",
				Constant = " ",
				Constructor = " ",
				Enum = " ",
				EnumMember = " ",
				Event = " ",
				Field = " ",
				File = " ",
				Folder = " ",
				Function = " ",
				Interface = " ",
				Keyword = " ",
				Method = " ",
				Module = " ",
				Operator = " ",
				Property = " ",
				Reference = " ",
				Snippet = " ",
				Struct = " ",
				Text = " ",
				TypeParameter = " ",
				Unit = " ",
				Value = " ",
				Variable = " ",
			},
		},

		snippets = {
			preset = "default", -- uses vim.snippet + friendly-snippets, no LuaSnip needed
		},

		completion = {
			accept = {
				auto_brackets = { enabled = true },
			},
			list = {
				selection = {
					preselect = true,
					auto_insert = false,
				},
			},
			menu = {
				border = "rounded",
				draw = {
					treesitter = { "lsp" },
					components = {
						kind_icon = {
							-- Tailwind color handling
							highlight = function(ctx)
								local lspkind = require("lspkind")
								local highlight = lspkind.cmp_format({ mode = "symbol" })
								local hl = highlight({}, ctx)

								local item = ctx.item
								local color = item.documentation
								if color and type(color) == "string" and color:match("^#%x%x%x%x%x%x$") then
									local hl_name = "tailwind_hex_" .. color:sub(2)
									if not vim.api.nvim_get_hl(0, { name = hl_name }).fg then
										vim.api.nvim_set_hl(0, hl_name, { fg = color })
									end
									return hl_name
								end

								return hl
							end,
						},
					},
				},
			},
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 200,
				window = { border = "rounded" },
			},
			ghost_text = { enabled = false },
		},

		sources = {
			default = { "lsp", "path", "snippets", "buffer", "lazydev" },
			per_filetype = {
				markdown = { "lsp", "path", "snippets", "buffer", "spell" },
				text = { "lsp", "path", "snippets", "buffer", "spell" },
			},
			providers = {
				lazydev = {
					name = "LazyDev",
					module = "lazydev.integrations.blink",
					score_offset = 100,
				},
				spell = {
					name = "Spell",
					module = "blink-cmp-spell",
					score_offset = -3,
					opts = { keep_all_entries = false },
				},
				buffer = {
					max_items = 30,
					min_keyword_length = 3,
				},
			},
		},

		cmdline = {
			enabled = true,
			sources = function()
				local type = vim.fn.getcmdtype()
				if type == "/" or type == "?" then
					return { "buffer" }
				end
				if type == ":" then
					return { "cmdline", "path" }
				end
				return {}
			end,
		},

		signature = { enabled = true, window = { border = "rounded" } },

		keymap = {
			preset = "none", -- we define everything manually below

			["<C-e>"] = { "hide", "fallback" },
			["<C-d>"] = { "hide_documentation", "fallback" },
			["<C-f>"] = { "scroll_documentation_down", "fallback" },
			["<C-b>"] = { "scroll_documentation_up", "fallback" },

			["<C-y>"] = { "select_and_accept", "fallback" },
			["<CR>"] = { "select_and_accept", "fallback" },

			["<C-j>"] = { "select_next", "fallback" },
			["<C-k>"] = { "select_prev", "fallback" },
			["<C-n>"] = { "select_next", "fallback" },
			["<C-p>"] = { "select_prev", "fallback" },
			["<Down>"] = { "select_next", "fallback" },
			["<Up>"] = { "select_prev", "fallback" },

			-- Tab: expand snippet or select next, with smart tab fallback
			["<Tab>"] = {
				function(cmp)
					if cmp.snippet_active() then
						return cmp.accept()
					end
				end,
				"select_next",
				"snippet_forward",
				"fallback",
			},

			-- Shift-Tab: jump back in snippet or select prev
			["<S-Tab>"] = {
				"select_prev",
				"snippet_backward",
				"fallback",
			},
		},
	},
}
