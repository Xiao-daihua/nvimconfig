return {
	dir = vim.fn.expand("~/.config/nvim/plugins/biblio"),
	lazy = false,
	config = function()
		require("biblio").setup({
			blog_root = vim.fn.expand("~/Code/Page/Xiao-daihua.github.io"),
		})
	end,
	keys = {
		{ "<leader>B", "<cmd>Biblio<cr>", desc = "Biblio: open dashboard" },
	},
}
