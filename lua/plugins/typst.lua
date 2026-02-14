return {
	{
		"chomosuke/typst-preview.nvim",
		lazy = false,
		version = "1.*",
		opts = {
			open_cmd = 'open -a "Safari" %s',
		},
		vim.keymap.set("n", "<leader>tp", ":TypstPreviewToggle<CR>", { desc = "Toggle Typst Preview" }),
		vim.keymap.set("n", "<leader>tf", vim.lsp.buf.format, { desc = "Format" }),
	},
	{
		"marnym/typst-watch.nvim",
		opts = {},
		ft = "typst",
	},
}
