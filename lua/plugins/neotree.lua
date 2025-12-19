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
          folder_closed = "",   -- 经典文件夹图标，满满文件夹感觉（ U+f07b）
          folder_open = "",     -- 打开的文件夹图标（ U+f07c）
          folder_empty = "",    -- 空文件夹图标，保持简洁（ U+f114）
          default = "",         -- 默认文件图标，像纸张（ U+f15c）
          highlight = "NeoTreeFileIcon",
        },
        modified = {
          symbol = "●",           -- 小圆点，比 [+] 更简洁优雅
          highlight = "NeoTreeModified",
        },
        git_status = {
          symbols = {
            added     = "",  -- 加号，新增文件
            modified  = "",  -- 修改，点点符号
            deleted   = "",  -- 删除，叉号
            renamed   = "➜",  -- 重命名，箭头
            ignored   = "◌",  -- 忽略，圆圈
            unstaged  = "",  -- 未暂存，铅笔
            staged    = "",  -- 已暂存，箭头圈
            conflict  = "",  -- 冲突，Git Merge 图标
          },
        },
      },
      highlight = {
        NeoTreeFileIcon = { fg = "#61afef" },       -- 天蓝色，文件图标
        NeoTreeFolderName = { fg = "#e5c07b", bold = true },  -- 金黄色，文件夹名
        NeoTreeModified = { fg = "#e06c75", bold = true },    -- 柔和红色，已修改标记
        NeoTreeGitAdded = { fg = "#98c379" },        -- 绿色，新增的文件
        NeoTreeGitModified = { fg = "#e5c07b" },     -- 黄色，git 修改
        NeoTreeGitDeleted = { fg = "#e06c75" },      -- 红色，git 删除
        NeoTreeGitRenamed = { fg = "#61afef" },      -- 蓝色，git 重命名
        NeoTreeGitUntracked = { fg = "#56b6c2" },    -- 青色，git 未跟踪
      },
      window = {
        position = "left", 
        width = 25,
        mappings = {
          ["<esc>"] = "close_window",
          ["l"] = "set_root",      -- 下一级目录作为根目录
          ["h"]  = "navigate_up", -- 返回上一级目录
          -- neotree自带的复制到剪切板功能是不可靠的，不能在mac上工作需要自己写一个。
          ["Y"] = function(state)
            local node = state.tree:get_node()
            if node then
              local path = node.path
              vim.fn.setreg("+", path) -- 复制到系统剪贴板
              print("Copied path: " .. path)
            end
          end,
        },
      },
      event_handlers = {
        {
          event = "file_opened",
          handler = function(file_path)
            if file_path:match("%.pdf$") then
              -- 使用 sioyek 打开 PDF
              vim.fn.jobstart({ "sioyek", file_path }, { detach = true })
              -- 关闭当前 buffer（防止 nvim 尝试打开 PDF）
              vim.cmd("bd!")
            end

            -- if file_path:match("%.html?$") then
            --   vim.fn.jobstart({ "open", file_path }, { detach = true })
            --   vim.cmd("bd!")  -- 关闭 buffer 防止在 nvim 打开
            -- end

          end,
        },
      },
      filesystem = {
        commands = {
          delete = function(state)
            local node = state.tree:get_node()
            if node == nil then return end
            local path = node.path
            -- 调用 trash-cli 命令
            local cmd = "trash " .. vim.fn.shellescape(path)
            os.execute(cmd)
            -- 刷新树
            state.commands.refresh(state)
          end,
        },

        filtered_items = {
          filtered_items = {
            visible = true, 
            hide_by_name = {
              ".git", ".DS_Store",
            },
            never_show = {        
              ".Trash",
            },
          },
          always_show = { ".make4ht", ".zshrc", ".config" },
        },
      },
    })
  end,
}
