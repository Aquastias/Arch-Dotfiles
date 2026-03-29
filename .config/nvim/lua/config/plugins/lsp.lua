return {
	"neovim/nvim-lspconfig",
	event = { "BufReadPre", "BufNewFile" },
	dependencies = {
		{ "mason-org/mason.nvim", config = true },
		"mason-org/mason-lspconfig.nvim",
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		{ "antosha417/nvim-lsp-file-operations", config = true },
		{
			"j-hui/fidget.nvim",
			opts = {
				notification = {
					window = { winblend = 0 },
				},
			},
		},
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
		-- NOTE: LSP Keybinds
		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
			callback = function(event)
				local map = function(keys, func, desc, mode)
					mode = mode or "n"
					vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
				end

				-- Disable neovim's default gr* mappings
				for _, key in ipairs({ "grn", "gra", "gri", "grr", "grt" }) do
					pcall(vim.keymap.del, "n", key, { buffer = event.buf })
				end

				-- NOTE: Using Snacks picker — no eager require, no duplicate mappings
				map("gd", function()
					Snacks.picker.lsp_definitions()
				end, "[G]oto [D]efinition")
				map("gr", function()
					Snacks.picker.lsp_references()
				end, "[G]oto [R]eferences")
				map("gI", function()
					Snacks.picker.lsp_implementations()
				end, "[G]oto [I]mplementation")
				map("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
				map("gt", function()
					Snacks.picker.lsp_type_definitions()
				end, "[G]oto [T]ype Definition")
				map("<leader>D", function()
					Snacks.picker.diagnostics_buffer()
				end, "Buffer [D]iagnostics")
				map("<leader>ds", function()
					Snacks.picker.lsp_symbols()
				end, "[D]ocument [S]ymbols")
				map("<leader>ws", function()
					Snacks.picker.lsp_workspace_symbols()
				end, "[W]orkspace [S]ymbols")
				map("<leader>rn", vim.lsp.buf.rename, "[R]e[n]ame")
				map("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction", { "n", "x" })
				map("<leader>vca", vim.lsp.buf.code_action, "See a[v]ailable [c]ode [a]ctions", { "n", "v" })
				map("<leader>ld", vim.diagnostic.open_float, "Show line diagnostics")
				map("K", vim.lsp.buf.hover, "Show documentation")
				map("<leader>rs", "<cmd>LspRestart<CR>", "Restart LSP")

				vim.keymap.set("i", "<C-h>", vim.lsp.buf.signature_help, {
					buffer = event.buf,
					desc = "LSP: Signature help",
				})

				local client = vim.lsp.get_client_by_id(event.data.client_id)

				if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
					local highlight_augroup = vim.api.nvim_create_augroup("lsp-highlight", { clear = false })
					vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
						buffer = event.buf,
						group = highlight_augroup,
						callback = vim.lsp.buf.document_highlight,
					})
					vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
						buffer = event.buf,
						group = highlight_augroup,
						callback = vim.lsp.buf.clear_references,
					})
					vim.api.nvim_create_autocmd("LspDetach", {
						group = vim.api.nvim_create_augroup("lsp-detach", { clear = true }),
						callback = function(event2)
							vim.lsp.buf.clear_references()
							vim.api.nvim_clear_autocmds({ group = "lsp-highlight", buffer = event2.buf })
						end,
					})
				end

				-- NOTE: Fixed source.fixAll -> source.fixAll.biome
				if client and client.name == "biome" then
					vim.api.nvim_create_autocmd("BufWritePre", {
						group = vim.api.nvim_create_augroup("BiomeFixAll", { clear = true }),
						buffer = event.buf,
						callback = function()
							vim.lsp.buf.code_action({
								context = {
									only = { "source.fixAll" },
									diagnostics = {},
								},
								apply = true,
							})
						end,
					})
				end

				if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
					map("<leader>ti", function()
						vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }))
					end, "[T]oggle [I]nlay Hints")
				end
			end,
		})

		-- NOTE: Diagnostics Setup
		local signs = {
			[vim.diagnostic.severity.ERROR] = " ",
			[vim.diagnostic.severity.WARN] = " ",
			[vim.diagnostic.severity.HINT] = "󰠠 ",
			[vim.diagnostic.severity.INFO] = " ",
		}

		local diag_augroup = vim.api.nvim_create_augroup("LspDiagnosticsHold", { clear = true })
		local virtual_text_enabled = true
		vim.o.updatetime = 350

		local function cursor_over_diagnostic()
			local bufnr = vim.api.nvim_get_current_buf()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local lnum, col = cursor[1] - 1, cursor[2]
			for _, diag in ipairs(vim.diagnostic.get(bufnr, { lnum = lnum })) do
				if diag.end_lnum == lnum and col >= diag.col and col < diag.end_col then
					return true
				end
			end
			return false
		end

		local function has_floating_win()
			for _, winid in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_config(winid).relative ~= "" then
					return true
				end
			end
			return false
		end

		local function update_diagnostic_config()
			vim.diagnostic.config({
				signs = { text = signs },
				virtual_text = virtual_text_enabled,
				underline = true,
				update_in_insert = true,
				float = {
					focusable = false,
					style = "minimal",
					border = "rounded",
					source = true,
				},
			})
		end

		update_diagnostic_config()

		vim.keymap.set("n", "<leader>lx", function()
			virtual_text_enabled = not virtual_text_enabled
			update_diagnostic_config()
		end, { desc = "Toggle LSP virtual text" })

		vim.keymap.set("n", "<leader>ll", function()
			virtual_text_enabled = not virtual_text_enabled
			update_diagnostic_config()
			vim.api.nvim_clear_autocmds({ group = diag_augroup })
			if not virtual_text_enabled then
				vim.api.nvim_create_autocmd("CursorHold", {
					group = diag_augroup,
					callback = function()
						if cursor_over_diagnostic() and not has_floating_win() then
							vim.diagnostic.open_float(nil, {
								focusable = false,
								close_events = {
									"CursorMoved",
									"CursorMovedI",
									"BufHidden",
									"InsertCharPre",
									"WinLeave",
								},
							})
						end
					end,
				})
			end
		end, { desc = "Toggle precise diagnostic hover" })

		-- NOTE: Capabilities — blink.cmp instead of cmp_nvim_lsp
		local capabilities = vim.tbl_deep_extend(
			"force",
			vim.lsp.protocol.make_client_capabilities(),
			require("blink.cmp").get_lsp_capabilities()
		)

		vim.lsp.config("*", { capabilities = capabilities })

		-- NOTE: Server configs
		local servers = {
			ts_ls = {
				capabilities = { documentFormattingProvider = false },
				filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
				single_file_support = true,
				init_options = {
					preferences = {
						includeCompletionsForModuleExports = true,
						includeCompletionsForImportStatements = true,
					},
				},
				settings = {
					javascript = { validate = { enable = false } },
				},
			},
			html = { filetypes = { "html", "twig", "hbs" } },
			cssls = {
				filetypes = { "css", "scss", "less" },
				init_options = { provideFormatter = true },
				single_file_support = true,
				settings = {
					css = { lint = { unknownAtRules = "ignore" }, validate = true },
					scss = { lint = { unknownAtRules = "ignore" }, validate = true },
					less = { lint = { unknownAtRules = "ignore" }, validate = true },
				},
			},
			tailwindcss = {
				filetypes = {
					"html",
					"css",
					"javascript",
					"typescript",
					"javascriptreact",
					"typescriptreact",
					"svelte",
					"vue",
					"astro",
				},
				init_options = { userLanguages = { astro = "html" } },
			},
			emmet_language_server = {
				filetypes = { "css", "html", "javascript", "javascriptreact", "less", "typescriptreact" },
				init_options = {
					includeLanguages = {},
					excludeLanguages = {},
					extensionsPath = {},
					preferences = {},
					showAbbreviationSuggestions = true,
					showExpandedAbbreviation = "always",
					showSuggestionsAsSnippets = false,
					syntaxProfiles = {},
					variables = {},
				},
			},
			emmet_ls = {
				filetypes = { "html", "typescriptreact", "javascriptreact", "css", "sass", "scss", "less", "svelte" },
			},
			gopls = {
				settings = {
					gopls = {
						analyses = { unusedparams = true },
						staticcheck = true,
						gofumpt = true,
					},
				},
			},
			dockerls = {},
			sqlls = {},
			jsonls = {},
			yamlls = {},
			marksman = {},
			astro = {},
			angularls = {},
			biome = {},
			lua_ls = {
				settings = {
					Lua = {
						completion = { callSnippet = "Replace" },
						runtime = { version = "LuaJIT" },
						workspace = {
							checkThirdParty = false,
							library = vim.api.nvim_get_runtime_file("", true),
						},
						diagnostics = {
							globals = { "vim", "Snacks" },
							disable = { "missing-fields" },
						},
						format = { enable = false },
					},
				},
			},
		}

		-- NOTE: Mason setup
		local ensure_installed = vim.tbl_keys(servers or {})
		vim.list_extend(ensure_installed, {
			"stylua",
			"prettier",
			"isort",
			"pylint",
			"clangd",
			"clang_format",
			"nixfmt",
		})
		require("mason-tool-installer").setup({ ensure_installed = ensure_installed })

		for server, cfg in pairs(servers) do
			cfg.capabilities = vim.tbl_deep_extend("force", {}, capabilities, cfg.capabilities or {})
			vim.lsp.config(server, cfg)
			vim.lsp.enable(server)
		end
	end,
}
