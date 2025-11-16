return {
  'folke/flash.nvim',
  event = 'VeryLazy',
  opts = {},
  keys = {
    {
      '<leader>j',
      mode = { 'n', 'x', 'o' },
      function()
        require('flash').jump()
      end,
      desc = '[J]ump with Flash',
    },
    {
      '<leader>J',
      mode = { 'n', 'x', 'o' },
      function()
        require('flash').treesitter()
      end,
      desc = '[J]ump Treesitter node',
    },
  },
}
