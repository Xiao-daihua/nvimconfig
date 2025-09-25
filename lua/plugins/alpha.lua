return {
  "goolord/alpha-nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local alpha = require("alpha")
    local dashboard = require("alpha.themes.dashboard")

    -- Header: 用 ASCII Art 拼出 X.D.H.
    dashboard.section.header.val = {
"",
"",
"",
"",
"",
      "                X . D . H               ",
    }

    -- 按钮快捷键
    dashboard.section.buttons.val = {
      dashboard.button("l", "  Lazy", ":Lazy<CR>"),
      dashboard.button("m", "  Mason", ":Mason<CR>"),
      dashboard.button("e", "  Neo-tree", ":Neotree toggle<CR>"),
      dashboard.button("c", "  Code", ":Neotree dir=~/code<CR>"),
      dashboard.button("n", "  Config", ":e ~/.config/nvim/<CR>"),
      dashboard.button("q", "  Quit", ":qa<CR>"),
    }

    alpha.setup(dashboard.config)

  end,
}

