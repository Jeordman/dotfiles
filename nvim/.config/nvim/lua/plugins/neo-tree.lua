return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',       -- Ensure plenary is available
    'nvim-tree/nvim-web-devicons', -- Optional, for icons
    'MunifTanjim/nui.nvim',        -- Required by neo-tree
  },
  cmd = 'Neotree',                 -- Lazy-load on `:Neotree` command
  keys = {
    {
      '<leader>b',
      ':Neotree action=focus position=right reveal=true<CR>',
      desc = 'Open NeoTree and reveal current file',
    },
  },
  config = function()
    require('neo-tree').setup {
      window = {
        position = 'right',
      },
    }
  end,
}
