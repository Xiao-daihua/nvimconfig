-- 这个是nvim使用的主要的配置文件
vim.cmd("set expandtab")
vim.cmd("set tabstop=2")
vim.cmd("set softtabstop=2")
vim.cmd("set shiftwidth=2")
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"


-- 行号显示
vim.opt.number = true
vim.opt.relativenumber = true

vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    vim.cmd("highlight LineNr guifg=#d19a66")
    vim.cmd("highlight CursorLineNr guifg=#fab387")
  end
})

vim.api.nvim_create_autocmd({ "InsertEnter" }, {
  pattern = "*",
  callback = function()
    vim.wo.relativenumber = false
  end
})
vim.api.nvim_create_autocmd({ "InsertLeave" }, {
  pattern = "*",
  callback = function()
    vim.wo.relativenumber = true
  end
})
--
-- -- 取消搜索后高亮快捷键
-- vim.keymap.set("n", "<Esc>", function()
--   vim.cmd("nohlsearch")
-- end, { desc = "Clear search highlight" })
--
-- -- 多窗口管理快捷键 
-- -- 设置快捷键
-- -- 1. 快捷键分屏管理
-- vim.api.nvim_set_keymap("n", "<leader>vs", ":vsplit<CR>", { noremap = true, silent = true })  -- 垂直分屏
-- vim.api.nvim_set_keymap("n", "<leader>hs", ":split<CR>", { noremap = true, silent = true })   -- 水平分屏
--
-- -- 2. 切换窗口（左右上下）
-- vim.api.nvim_set_keymap("n", "<leader>w", "<C-w>w", { noremap = true, silent = true })        -- 切换窗口
-- vim.api.nvim_set_keymap("n", "<leader>h", "<C-w>h", { noremap = true, silent = true })        -- 切换到左边窗口
-- vim.api.nvim_set_keymap("n", "<leader>j", "<C-w>j", { noremap = true, silent = true })        -- 切换到下边窗口
-- vim.api.nvim_set_keymap("n", "<leader>k", "<C-w>k", { noremap = true, silent = true })        -- 切换到上边窗口
-- vim.api.nvim_set_keymap("n", "<leader>l", "<C-w>l", { noremap = true, silent = true })        -- 切换到右边窗口
--
-- -- 3. 快捷调整窗口大小
-- -- 配置快捷键，使得按住 Ctrl 后按箭头键持续调整窗口大小
-- vim.api.nvim_set_keymap("n", "<S-Up>", ":resize +2<CR>", { noremap = true, silent = true })
-- vim.api.nvim_set_keymap("n", "<S-Down>", ":resize -2<CR>", { noremap = true, silent = true })
-- vim.api.nvim_set_keymap("n", "<S-Left>", ":vertical resize -2<CR>", { noremap = true, silent = true })
-- vim.api.nvim_set_keymap("n", "<S-Right>", ":vertical resize +2<CR>", { noremap = true, silent = true })
--
-- -- 4. 关闭窗口快捷键
-- -- 关闭当前窗口并保存（:wq）
-- vim.api.nvim_set_keymap("n", "<leader>q", ":w<CR>:q<CR>", { noremap = true, silent = true })
-- -- 关闭所有窗口并保存（保存所有文件并退出）
-- vim.api.nvim_set_keymap("n", "<leader>Q", ":wa | :qa<CR>", { noremap = true, silent = true })
--
-- -- 实现复制到剪切板的快捷键(注意这个是在可视模式下面的模板)
-- vim.api.nvim_set_keymap('v', '<leader>y', '"+y', { noremap = true, silent = true })
--
-- 插入keymaps
require("keymaps.general") 
require("keymaps.tex")

-- 插件系统的配置文件
require("config.lazy")

