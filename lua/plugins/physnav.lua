return {
	dir = vim.fn.expand("~/.config/nvim/plugins/physnav"),
	lazy = false,
	config = function()
		require("physnav").setup({
			root = vim.fn.expand("~/Code/Notes/Phys"),
			categories = { "EPFL_lecture", "Notes", "RG" },
		})
	end,
	keys = {
		{ "<leader>N", "<cmd>PhysNav<cr>", desc = "PhysNav: open browser" },
	},
}
