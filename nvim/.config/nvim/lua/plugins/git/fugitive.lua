return {
  'tpope/vim-fugitive',
  cmd = { 'Git', 'Gdiff', 'Gstatus', 'Gblame' }, -- These are the commands that trigger fugitive
  keys = {
    {
      '<leader>gs',
      ':horizontal G | only<CR>',
      desc = 'Git status in horizontal split',
      silent = true,
    },
    {
      '<leader>gd',
      ':vertical Gdiff<CR>',
      desc = 'Git diff in vertical split',
      silent = true,
    },
    {
      '<leader>gf',
      ':diffget //3<CR>',
      desc = 'Git diffget to resolve conflicts',
      silent = true,
    },
    {
      '<leader>gp',
      ':Git push<cr>',
      desc = 'Git push',
      silent = true,
    },
    {
      '<leader>gpu',
      ':Git push -u origin HEAD<cr>',
      desc = 'Git push origin head',
      silent = true,
    },
    {
      '<leader>gpp',
      function()
        vim.cmd.Git { 'pull', '--rebase' }
      end,
      desc = 'Git pull',
      silent = true,
    },
    {
      '<leader>gc',
      ':<C-u>lua local s,e = vim.fn.line("\'<"), vim.fn.line("\'>"); local f = vim.fn.expand("%:."); local ref = (s == e) and (f .. ":" .. s) or (f .. ":" .. s .. "-" .. e); vim.fn.setreg("+", ref); print("Copied: " .. ref)<CR>',
      desc = 'Copy file:lines reference',
      mode = 'v', -- Visual mode only
      silent = true,
    },
  },
  config = function()
    -- Custom configurations for vim-fugitive can go here
  end,
}
