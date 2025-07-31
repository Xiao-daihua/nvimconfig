return {
    'numToStr/Comment.nvim',
    opts = {
        -- add any options here
    },
  config = function()
    require("Comment").setup({
      toggler = {
        line = "gcc",    -- 切换行注释
        block = "gbc",   -- 切换块注释
      },
      opleader = {
        line = "gc",     -- 操作符快捷键，视觉模式用
        block = "gb",    -- 操作符快捷键，视觉模式用
      },
    })
  end
}
