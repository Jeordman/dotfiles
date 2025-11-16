--  NOTE: Must happen befoautopairsre plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- turn off line wrapping
vim.opt.wrap = false

-- colorcolumn is a vertical line at the specified column number
vim.opt.colorcolumn = '80'

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = true

-- Enable mouse mode, can be useful for resizing splits for example!
vim.opt.mouse = 'a'

-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Sync clipboard between OS and Neovim.
--  Schedule the setting after `UiEnter` because it can increase startup-time.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.schedule(function()
  vim.opt.clipboard = 'unnamedplus'
end)

-- Enable break indent
vim.opt.breakindent = true

-- Save undo history
vim.opt.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Keep signcolumn on by default
vim.opt.signcolumn = 'yes'

-- Decrease update time
vim.opt.updatetime = 250

-- Decrease mapped sequence wait time
vim.opt.timeoutlen = 300

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.opt.inccommand = 'split'

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 10

-- if performing an operation that would fail due to unsaved changes in the buffer (like `:q`),
-- instead raise a dialog asking if you wish to save the current file(s)
-- See `:help 'confirm'`
vim.opt.confirm = true

-- [[ Basic Keymaps ]]
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code [A]ction' })
vim.keymap.set('n', '<leader>cs', vim.diagnostic.open_float, { desc = '[C]urrent diagnostic [S]how' })

vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

vim.api.nvim_create_user_command('ChangeRoot', function()
  -- Get the full path of the current file's directory
  local current_file_dir = vim.fn.fnamemodify(vim.fn.expand '%:p', ':h')

  -- Change Neovim's current working directory
  vim.cmd('cd ' .. current_file_dir)

  print('Changed CWD to: ' .. current_file_dir)
end, { desc = 'Change CWD to current file directory' })

-- Keymap for the new command
vim.keymap.set('n', '<leader>cd', ':ChangeRoot<CR>', { desc = 'Change [C]WD to Git [D]irectory root' })

-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- -- Set autoread option
-- vim.o.autoread = true
--
-- -- Autocmds to check for changes when Neovim gains focus, enters a buffer, or is idle
-- vim.api.nvim_create_augroup('CheckForChanges', { clear = true })
-- vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
--   group = 'CheckForChanges',
--   callback = function()
--     if vim.fn.mode() ~= 'c' then -- Avoid running in command mode
--       vim.cmd 'checktime'
--     end
--   end,
-- })

-- -- Optional: Add a notification after a file has been reloaded from disk
-- vim.api.nvim_create_autocmd({ 'FileChangedShellPost' }, {
--   group = 'CheckForChanges',
--   callback = function()
--     vim.notify('File changed on disk. Buffer reloaded.', vim.log.levels.INFO, {})
--   end,
-- })

-- override :e to refresh all buffers, staying on the current buffer
vim.api.nvim_create_autocmd('CmdlineLeave', {
  pattern = '*',
  callback = function()
    if vim.fn.getcmdline():match('^e!?$') then
      vim.schedule(function()
        local current_buf = vim.api.nvim_get_current_buf()
        vim.cmd('bufdo e')
        vim.api.nvim_set_current_buf(current_buf)
      end)
    end
  end
})
