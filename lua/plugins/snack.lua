return {
  "folke/snacks.nvim",
  lazy = false,
  priority = 1000,
  opts = {
    terminal = {
      bo = {
        filetype = "snacks_terminal",
        buflisted = false,  -- 终端buffer不列在buffer列表中，减少干扰
        bufhidden = "hide", -- 关闭时隐藏buffer，防止意外丢失
      },
      wo = {
        number = false,    -- 终端里不显示行号
        relativenumber = false,
        signcolumn = "no",
      },
      keys = {
        q = "hide", -- normal mode下面使用q就是hide这个terminal
        gf = function(self)
          local f = vim.fn.findfile(vim.fn.expand("<cfile>"), "**")
          if f == "" then
            Snacks.notify.warn("No file under cursor")
          else
            self:hide()
            vim.schedule(function()
              vim.cmd("e " .. f)
            end)
          end
        end,
        term_normal = {
          "<esc>",
          function(self)
            self.esc_timer = self.esc_timer or (vim.uv or vim.loop).new_timer()
            if self.esc_timer:is_active() then
              self.esc_timer:stop()
              vim.cmd("stopinsert")
            else
              self.esc_timer:start(200, 0, function() end)
              return "<esc>"
            end
          end,
          mode = "t",
          expr = true,
          desc = "Double escape to normal mode",
        },
      },
    },
  },
}
