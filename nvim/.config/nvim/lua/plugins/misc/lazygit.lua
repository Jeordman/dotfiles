return {
  'kdheepak/lazygit.nvim',
  lazy = true,
  cmd = {
    'LazyGit',
    'LazyGitConfig',
    'LazyGitCurrentFile',
    'LazyGitFilter',
    'LazyGitFilterCurrentFile',
  },
  -- optional for floating window border decoration
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  -- setting the keybinding for LazyGit with 'keys' is recommended in
  -- order to load the plugin when the command is run for the first time
  keys = {
    { '<leader>ga', '<cmd>LazyGit<cr>', desc = 'LazyGit' },
  },
  config = function()
    -- lazygit has no background setting of its own, so the float's bg is what
    -- shows through its panels. #161616 is herdr's sidebar_bg.
    local function set_lazygit_hl()
      vim.api.nvim_set_hl(0, 'LazyGitFloat', { bg = '#161616' })
      vim.api.nvim_set_hl(0, 'LazyGitBorder', { fg = '#3A3A3A', bg = '#161616' })
    end

    set_lazygit_hl()
    vim.api.nvim_create_autocmd('ColorScheme', {
      callback = set_lazygit_hl,
      desc = 'Reapply LazyGit float highlights',
    })
  end,
}
