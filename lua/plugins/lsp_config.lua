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
				root_markers = { ".git", "typst.toml" }, -- 可选但推荐
				settings = {
					exportPdf = "onSave", -- 保存时自动导出 PDF
					semanticTokens = "enable", -- 语义高亮
					formatterMode = "typstyle", -- or "typstfmt"
					formatterProseWrap = true, -- wrap lines in content mode
					formatterPrintWidth = 80, -- limit line length to 80 if possible
					formatterIndentSize = 4, -- indentation width
				},
			})

			-- LSP常用的快捷键
			vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to Definition" })
			vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover Info" })
			-- vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename" })
			vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code Action" })
			-- vim.keymap.set("n", "gr", vim.lsp.buf.references, { desc = "References" })
			vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Show diagnostics" })
		end,
	},
}
