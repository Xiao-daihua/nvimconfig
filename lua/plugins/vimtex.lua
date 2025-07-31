return {

  {
    "lervag/vimtex",
    lazy = false,     -- we don't want to lazy load VimTeX
    -- tag = "v2.15", -- uncomment to pin to a specific release
    init = function()

      vim.g.vimtex_view_method = 'sioyek'
      -- 报错的提示！
      vim.g.vimtex_quickfix_mode = 0   -- 不自动打开 quickfix
      vim.g.vimtex_quickfix_open_on_warning = 0  -- 警告不打开 quickfix
      vim.g.vimtex_quickfix_open_on_error = 1    -- 仅报错时打开

      vim.g.vimtex_syntax_enabled = 0 -- 关掉syntax，因为我有treesitter可以进行高亮

      -- latexmk 配置，使用 xelatex + bibtex
      vim.g.vimtex_compiler_method = 'latexmk'
      vim.g.vimtex_compiler_latexmk_engines = {
        _ = '-xelatex'
      }
      vim.g.vimtex_compiler_latexmk = {
        build_dir = 'build',
        executable = 'latexmk',
        options = {
          '-bibtex',
          '-synctex=1',
          '-interaction=nonstopmode',
          '-file-line-error',
          '-shell-escape',
          '-verbose',
        },
        continuous = 1,
        callback = 1,
      }

    end
  },
  {
    "HakonHarnes/img-clip.nvim",
    event = "VeryLazy",
    opts = {
    },
    keys = {
      -- suggested keymap
      { "<leader>p", "<cmd>PasteImage<cr>", desc = "Paste image from system clipboard" },
    },
  }

}
