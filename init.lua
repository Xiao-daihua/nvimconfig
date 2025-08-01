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


-- 快捷键绑定（例如放在 lua/config/keymaps.lua 或 init.lua 中）
vim.keymap.set("n", "<leader>tt", function()
  local dir = vim.fn.expand("%:p:h") -- 获取当前文件所在的目录
  require("snacks").terminal(nil, {
    cwd = dir, -- 设置终端工作目录
    win = {
      split = "below", -- 水平打开在下方
      position = "bottom", -- 定位到底部
      height = 0.3, -- 占用屏幕 30%
    },
    auto_insert = true, -- 自动进入插入模式
    auto_close = false, -- 终端退出后不自动关闭窗口
  })
end, { desc = "打开 snacks 终端并 cd 到当前目录" })
