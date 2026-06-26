return {
	{
		"chomosuke/typst-preview.nvim",
		lazy = false,
		version = "1.*",
		opts = {
			open_cmd = "open -a Safari %s && ",
			follow_cursor = false,
			dependencies_bin = {
				tinymist = vim.fn.expand("~/.local/share/nvim/mason/bin/tinymist"),
			},
			extra_args = {
				"--partial-rendering=true",
			},
		},
		-- vim.keymap.set("n", "<leader>tf", vim.lsp.buf.format, { desc = "Format" }),
		vim.keymap.set("n", "<leader>tp", "<cmd>TypstPreviewToggle<CR>", { desc = "Typst Preview Toggle" }),
	},
}
