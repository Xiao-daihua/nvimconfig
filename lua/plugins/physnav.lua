return {
	dir = vim.fn.expand("~/.config/nvim/plugins/physnav"),
	lazy = false,
	config = function()
		require("physnav").setup({
			root = vim.fn.expand("~/Code/Notes/Phys"), -- 你的笔记根目录
		})
	end,
	keys = {
		{ "<leader>N", "<cmd>PhysNav<cr>", desc = "PhysNav: open browser" },
	},
}
