return {
	"stevearc/conform.nvim",
	opts = {
		format_on_save = function(bufnr)
			local lsp_format_opt = "never"
			return {
				timeout_ms = 500,
				lsp_format = lsp_format_opt,
			}
		end,
		formatters_by_ft = {
			lua = { "stylua" },
			python = { "black" },
			tex = { "tex-fmt" },
			typst = { "typstyle" },
		},
	},
}
