
-- Bootstrap lazy.nvim 这个内容实际上说的就是，查看是否存在lazy的一个文件，如果存在就给一个path
-- 如果不存在就从git上面clone一个文件夹进去
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)


-- Setup lazy.nvim 这里是真正的lazy的配置区域
require("lazy").setup({
  spec = { { import = "plugins" }},
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { "catppuccin" } },
  -- automatically check for plugin updates
  checker = { enabled = true },
  ui = {
    border = "rounded", -- 例子，改边框
    custom_keys = {
      ["<esc>"] = function(plugin)
        -- 相当于执行 :q
        vim.cmd("close")
      end,
    },
  },
})






