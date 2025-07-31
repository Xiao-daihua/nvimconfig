return{
  {
    "mason-org/mason.nvim",
    opts = {},
    config = function()
      require("mason").setup({
        providers = {
          "mason.providers.registry-api",
          "mason.providers.client",
        },
        pip = {
          install_args = { "-i", "https://pypi.tuna.tsinghua.edu.cn/simple" },
        },
        github = {
          download_url_template = "https://github.com/%s/releases/download/%s/%s",
        },
      })
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {},
    dependencies = {
      { "mason-org/mason.nvim", opts = {} },
      "neovim/nvim-lspconfig",
    },
    config = function()
      require("mason-lspconfig").setup({
        -- 这里我们填写所有的需要的代码系统
        ensure_installed = {'lua_ls','pyright','clangd','marksman','texlab'}
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      -- 匹配snippet cmp nvim lsp的操作
      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      -- 这里我们配置我们支持的每一种语言
      -- Lua语言
      local lspconfig = require("lspconfig")
      lspconfig.lua_ls.setup({
        capabilities = capabilities,

        settings = {
          Lua = {
            diagnostics = {
              globals = { "vim" },
            },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            telemetry = { enable = false },
          },
        },
      })
      -- python
      lspconfig.pyright.setup({
        capabilities = capabilities,
      })

      -- C/Cpp
      lspconfig.clangd.setup({
        capabilities = capabilities,
      })

      -- markdown
      lspconfig.marksman.setup({
        capabilities = capabilities,
      })

      -- latex
      lspconfig.texlab.setup({
        capabilities = capabilities,
        settings = {
          texlab = {
            build = {
              executable = "latexmk",
              args = { "-pdf", "-interaction=nonstopmode", "-synctex=1", "%f" },
              onSave = true,  -- 保存时自动编译
              forwardSearchAfter = true,
            },
            forwardSearch = {
              executable = "zathura",  -- 或 Skim, Evince 等
              args = { "--synctex-forward", "%l:1:%f", "%p" },
            },
          },
        },
      })

      -- LSP常用的快捷键
      vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to Definition" })
      vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover Info" })
      -- vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename" })
      vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code Action" })
      -- vim.keymap.set("n", "gr", vim.lsp.buf.references, { desc = "References" })
      vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Show diagnostics" })
    end,
  }
}
