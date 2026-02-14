-- lua/keymap/tex.lua

local opts = { buffer = true, noremap = true, silent = true }
local keymap = vim.keymap.set

vim.api.nvim_create_autocmd("FileType", {
	pattern = "tex",
	callback = function()
		vim.keymap.set("i", "<C-e>", "$  $<Left><Left>", { buffer = true })
		vim.keymap.set("i", "<C-j>", "\\textbf{}<Left>", { buffer = true })
		vim.keymap.set("i", "<C-h>", "\\hlr{}<Left>", { buffer = true })
		vim.keymap.set("i", "<C-k>", "\\textit{}<Left>", { buffer = true })
		vim.keymap.set("i", "<C-g>", "\\sout{}<Left>", { buffer = true })
		vim.keymap.set("i", "<C-r>", "\\cref{}<Left>", { buffer = true })
		vim.keymap.set("i", "<C-l>", "\\label{}<Left>", { buffer = true })
	end,
})
