return {
	{
		"mason-org/mason.nvim",
		opts = {},
		config = function()
			require("mason").setup({
				providers = {
					"mason.providers.registry-api",
					"mason.providers.client",
				},
				pip = {
					install_args = { "-i", "https://pypi.tuna.tsinghua.edu.cn/simple" },
				},
				github = {
					download_url_template = "https://github.com/%s/releases/download/%s/%s",
				},
			})
		end,
	},
	{
		"mason-org/mason-lspconfig.nvim",
		opts = {},
		dependencies = {
			{ "mason-org/mason.nvim", opts = {} },
			"neovim/nvim-lspconfig",
		},
		config = function()
			require("mason-lspconfig").setup({
				-- 这里我们填写所有的需要的代码系统
				ensure_installed = { "lua_ls", "pyright", "clangd", "marksman", "texlab", "tinymist" },
			})
		end,
	},
	{
		"neovim/nvim-lspconfig",
		config = function()
			-- 匹配snippet cmp nvim lsp的操作
			local capabilities = require("cmp_nvim_lsp").default_capabilities()

			-- 全局能力配置
			vim.lsp.config("*", {
				capabilities = capabilities,
			})

			-- Lua
			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						diagnostics = { globals = { "vim" } },
						workspace = {
							library = vim.api.nvim_get_runtime_file("", true),
							checkThirdParty = false,
						},
						telemetry = { enable = false },
					},
				},
			})

			-- Python
			vim.lsp.config("pyright", {
				capabilities = capabilities,
			})

			-- C / C++
			vim.lsp.config("clangd", {
				capabilities = capabilities,
			})

			-- Markdown
			vim.lsp.config("marksman", {
				capabilities = capabilities,
			})

			-- LaTeX
			vim.lsp.config("texlab", {
				capabilities = capabilities,
			})

			-- Typst (tinymist)
			vim.lsp.config("tinymist", {
				cmd = { "tinymist" },
				filetypes = { "typst" },
				root_markers = { ".git", "typst.toml" },
				settings = {
					semanticTokens = "enable",
					formatterMode = "typstyle",
					formatterProseWrap = true,
					formatterPrintWidth = 80,
					formatterIndentSize = 4,
				},
				on_attach = function(client, bufnr)
					vim.defer_fn(function()
						local root = client.config.root_dir
						if root then
							local candidates = { "main.typ", "thesis.typ", "index.typ" }
							for _, name in ipairs(candidates) do
								local path = root .. "/" .. name
								if vim.fn.filereadable(path) == 1 then
									-- 关键：用 client:exec_cmd 而不是 vim.lsp.buf.execute_command
									-- 这样只发给 tinymist，不会广播给 Copilot
									client:exec_cmd({
										title = "pin",
										command = "tinymist.pinMain",
										arguments = { path },
									}, { bufnr = bufnr })
									break
								end
							end
						end
					end, 100)
				end,
			})
			-- LSP常用的快捷键
			vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to Definition" })
			vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover Info" })
			-- vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename" })
			vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code Action" })
			-- vim.keymap.set("n", "gr", vim.lsp.buf.references, { desc = "References" })
			vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Show diagnostics" })
		end,
	},
}
