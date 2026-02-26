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

			vim.lsp.config("tinymist", {
				cmd = { "tinymist" },
				filetypes = { "typst" },
				root_markers = { "typst.toml" },
				on_attach = function(client, bufnr)
					if client.name == "tinymist" then
						local main = vim.fn.fnamemodify(client.root_dir .. "/main.typ", ":p")
						client.request("workspace/executeCommand", {
							command = "tinymist.pinMain",
							arguments = { main },
						})
					end
				end,
				settings = {
					semanticTokens = "enable",
					formatterMode = "typstyle",
					formatterProseWrap = true,
					formatterPrintWidth = 85,
					formatterIndentSize = 4,
					exportPdf = "onType",
				},
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
