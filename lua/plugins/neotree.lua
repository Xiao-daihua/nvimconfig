---@diagnostic disable: missing-fields
return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons", -- optional, but recommended
  },
  lazy = false, -- neo-tree will lazily load itself

  config = function()

    vim.keymap.set("n", "<leader>e", ":Neotree toggle<CR>", { noremap = true, silent = true, desc = "打开 Neo-tree" })
    vim.keymap.set("n", "<leader>E", function()
      local filepath = vim.fn.expand("%:p:h") -- 当前文件的目录
      vim.cmd("Neotree " .. filepath)
    end, { desc = "打开文件所在文件夹" })


    require("neo-tree").setup({
      enable_git_status = true,
      enable_diagnostics = true,
      default_component_configs = {
        indent = {
          with_markers = false,
        },
        icon = {
          folder_closed = "",
          folder_open = "",
          folder_empty = "",
          default = "",
          highlight = "NeoTreeFileIcon",
        },
        modified = {
          symbol = "[+]",
          highlight = "NeoTreeModified",
        },
        git_status = {
          symbols = {
            added     = "✚",
            modified  = "",
            deleted   = "✖",
            renamed   = "➜",
            untracked = "",
            ignored   = "",
            unstaged  = "",
            staged    = "",
            conflict  = "",
          },
        },
      },
      window = {
        position = "float", 
        popup = {
          size = {
            height = "80%",
            width = "60%",
          },
          position = "50%", 
          border = {
            style = "rounded", 
          },
        },
        mappings = {
          ["<esc>"] = "close_window",
          ["<Right>"] = "set_root",      -- 下一级目录作为根目录
          ["<Left>"]  = "navigate_up", -- 返回上一级目录
          ["yy"] = "copy_to_clipboard",   -- 复制文件路径
        },
      },

      filesystem = {
        filtered_items = {
          filtered_items = {
            visible = true,          -- 显示被隐藏规则过滤的文件
            hide_dotfiles = true,    -- 默认隐藏点文件
            hide_gitignored = true,  -- 默认隐藏 .gitignore 的文件
            hide_by_name = {         -- 按名字隐藏
              ".git", ".DS_Store",
              -- 不要在这里写 .zshrc 和 .config
            },
            never_show = {           -- 永远不要显示的文件/文件夹
              ".Trash",
            },
          },
          always_show = { ".zshrc", ".config" },  -- 指定始终显示的文件夹和文件
        },
      },
    })
  end,
}
