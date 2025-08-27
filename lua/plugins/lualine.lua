return {
  'nvim-lualine/lualine.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    require('lualine').setup {
      options = {
        theme = 'rose-pine',
        icons_enabled = true,
        component_separators = { left = '', right = '' },
        -- section_separators = { left = '', right = '' },
        disabled_filetypes = {
          statusline = { 'NvimTree', 'neo-tree', 'alpha', 'starter' }, -- 首页和侧边栏禁用
          winbar = {},
        },
        always_divide_middle = true,
      },
      sections = {
        lualine_a = { { 'mode', icon = '' } },
        lualine_b = { { 'branch', icon = '' }, 'diff', 'diagnostics' },
        lualine_c = { { 'filename', path = 1 } },
        lualine_x = { 'encoding','filetype' },
        lualine_y = { { 'progress', icon = '' } },
        lualine_z = { 'location' }
      },
      inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = { 'filename' },
        lualine_x = { 'location' },
        lualine_y = {},
        lualine_z = {}
      },
      extensions = { 'neo-tree', 'lazy', 'quickfix', 'man' }
    }
  end,
}
