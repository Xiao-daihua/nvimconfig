return {
  -- {
  --   "folke/tokyonight.nvim",
  --   lazy = false,
  --   priority = 1000,
  --   opts = {},
  --   config = function()
  --     vim.cmd([[colorscheme tokyonight-storm]])
  --   end,
  -- },
  -- {
  --   "catppuccin/nvim", 
  --   name = "catppuccin", 
  --   priority = 1000,
  --   config = function()
  --     vim.cmd.colorscheme "catppuccin"
  --   end
  -- },
  {
    "rose-pine/neovim",
    name = "rose-pine",
    config = function()
      require("rose-pine").setup({
        variant = "moon", -- 🌙 这里切换成 moon
        disable_background = false,
        disable_float_background = false,
        disable_italics = false,
      })
      vim.cmd("colorscheme rose-pine")
    end,
  },
} 
