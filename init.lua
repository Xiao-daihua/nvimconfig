-- 这个是nvim使用的主要的配置文件
vim.cmd("set expandtab")
vim.cmd("set tabstop=2")
vim.cmd("set softtabstop=2")
vim.cmd("set shiftwidth=2")
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- 开启行号与相对行号
vim.opt.number = true
vim.opt.relativenumber = true

-- 高亮方案更简洁
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    -- 普通行号：淡灰色，低调
    vim.cmd("highlight LineNr guifg=#5c6370")  -- 比如 OneDark 的灰色
    -- 当前行号：橙色高亮
    vim.cmd("highlight CursorLineNr guifg=#fab387")
  end
})

-- 插入模式自动关闭相对行号（提高可读性）
vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    vim.wo.relativenumber = false
  end
})

vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function()
    vim.wo.relativenumber = true
  end
})


-- 插入keymaps
require("keymaps.general") 
require("keymaps.tex")

-- 插件系统的配置文件
require("config.lazy")

