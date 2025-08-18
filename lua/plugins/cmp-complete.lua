return {
  {
    "hrsh7th/cmp-nvim-lsp", 
  },
  {
    "L3MON4D3/LuaSnip",
    dependencies ={
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets"
    },
  },
  {
    "hrsh7th/nvim-cmp",
    config = function()
      local cmp = require'cmp'
      -- vscode类型的snippet的加入
      require("luasnip.loaders.from_vscode").lazy_load()
      -- 自定义的snippet的加入
      require("luasnip.loaders.from_lua").lazy_load({ paths = "~/.config/nvim/lua/snippet" })
      -- latex的snippet路径加入
      local snippet_path = vim.fn.expand("~/.config/nvim/lua/snippet/tex")
      require("luasnip.loaders.from_lua").lazy_load({
        paths = snippet_path,
      })


      cmp.setup({
        snippet = {
          -- REQUIRED - you must specify a snippet engine
          expand = function(args)
            require('luasnip').lsp_expand(args.body) -- For `luasnip` users.我先使用luasnip实现所有的snippet，如果使用其他插件则选择对应的
          end,
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' }, -- For luasnip users.
          { name = 'render-markdown' },
        }, {
            { name = 'buffer' },
          })
      }) 
    end,
  }
}
