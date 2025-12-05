return {
  'sindrets/diffview.nvim',
  dependencies = 'nvim-lua/plenary.nvim',
  opts = {
    keymaps = {
      view = {
        { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Close diffview' } },
      },
      file_panel = {
        { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Close diffview' } },
      },
    },
  },
  keys = {
    {
      '<leader>gm',
      function()
        -- Check if origin/main exists, otherwise use origin/master
        local handle = io.popen 'git rev-parse --verify origin/main 2>/dev/null'
        local result = handle:read '*a'
        handle:close()

        local base = (result ~= '') and 'origin/main' or 'origin/master'
        vim.cmd('DiffviewOpen ' .. base .. '...HEAD')
      end,
      desc = 'Git Review against main/master',
    },
    {
      '<leader>gss',
      function()
        vim.cmd 'DiffviewOpen origin/staging...HEAD'
      end,
      desc = 'Git Review against staging',
    },
  },
}
