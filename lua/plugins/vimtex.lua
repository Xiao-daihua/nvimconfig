return {
  {
    "lervag/vimtex",
    lazy = false,     -- we don't want to lazy load VimTeX
    -- tag = "v2.15", -- uncomment to pin to a specific release
    init = function()
      vim.g.vimtex_compiler_start_on_edit = 0
      vim.g.vimtex_compiler_start_on_save = 0
      vim.g.vimtex_compiler_autoload = 0
      vim.g.vimtex_compiler_method = 'latexmk'
      vim.g.vimtex_compiler_latexmk = {
        continuous = 0,
        executable = 'latexmk',
        options = {
          '-synctex=1',
          '-interaction=nonstopmode',
          '-file-line-error',
          '-shell-escape',
          '-verbose',
        },
      }
      vim.g.vimtex_compiler_latexmk_engines = {
        _ = '-xelatex'
      }

      vim.g.vimtex_view_method = 'sioyek'
       -- 报错的提示！
      vim.g.vimtex_quickfix_mode = 1   -- 不自动打开 quickfix
      vim.g.vimtex_quickfix_open_on_warning = 0  -- 警告不打开 quickfix
      vim.g.vimtex_quickfix_open_on_error = 1    -- 仅报错时打开
      vim.g.vimtex_syntax_enabled = 0 -- 关掉syntax，因为我有treesitter可以进行高亮
    end
  },
  {
    "evesdropper/luasnip-latex-snippets.nvim",
  },
  {
    "HakonHarnes/img-clip.nvim",
    event = "VeryLazy",
    opts = {
      default = {
        -- 将图片保存目录设为当前 buffer 文件的所在目录（如 foo.tex 所在路径）
        -- dir_path                = ".",
        relative_to_current_file = true,
        extension               = "png",
        -- file_name               = "%Y-%m-%d-%H-%M-%S",
        use_absolute_path       = false,
        prompt_for_file_name    = true,
        insert_template_after_cursor = true,
      },
      filetypes = {
        tex = {
          -- 下面可以修改模板！
          template = [[
\begin{figure}[H]
  \centering
  \includegraphics[width=0.75\textwidth]{$FILE_PATH}
  \caption{$CURSOR}
  \label{fig:$LABEL}
\end{figure}
        ]],
          -- 你可以加以覆盖，例如调整路径行为
          relative_template_path = true,
        },
      },
    },
    keys = {
      -- suggested keymap
      { "<leader>p", "<cmd>PasteImage<cr>", desc = "Paste image from system clipboard" },
    },
  }
}
