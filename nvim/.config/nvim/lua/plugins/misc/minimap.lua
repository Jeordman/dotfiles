return {
  {
    'Isrothy/neominimap.nvim',
    version = 'v3.x.x',
    lazy = false,
    init = function()
      vim.opt.wrap = false
      vim.opt.sidescrolloff = 36

      vim.g.neominimap = {
        auto_enable = false,
        layout = 'split',
        split = {
          direction = 'right',
          width = 20,
        },
        click = { enabled = true },
        exclude_filetypes = { 'neo-tree', 'help', 'lazy', 'mason', 'TelescopePrompt' },
        exclude_buftypes = { 'nofile', 'nowrite', 'quickfix', 'terminal', 'prompt' },
      }

      vim.keymap.set('n', '<leader>mm', '<cmd>Neominimap Toggle<cr>', { desc = 'Minimap toggle' })
      vim.keymap.set('n', '<leader>mo', '<cmd>Neominimap Enable<cr>', { desc = 'Minimap on' })
      vim.keymap.set('n', '<leader>mc', '<cmd>Neominimap Disable<cr>', { desc = 'Minimap off' })
      vim.keymap.set('n', '<leader>mf', '<cmd>Neominimap Focus<cr>', { desc = 'Minimap focus' })
      vim.keymap.set('n', '<leader>mu', '<cmd>Neominimap BufRefresh<cr>', { desc = 'Minimap refresh' })
    end,
  },
}
