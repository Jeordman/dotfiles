--  NOTE: Must happen befoautopairsre plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- turn off line wrapping
vim.opt.wrap = false

-- colorcolumn is a vertical line at the specified column number
vim.opt.colorcolumn = '80'

-- Preserve original file line endings
vim.opt.fileformats = 'unix,dos,mac' -- Detect all formats (unix first = default for new files)
vim.opt.fixendofline = false -- Don't add missing EOL at end of file

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

-- [[ Folding Configuration ]]
-- Use indent-based folding for simplicity
vim.opt.foldmethod = 'indent'
-- Start with all folds open
vim.opt.foldenable = true
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
-- Show fold column in the gutter (0 to hide, 1 to show minimal)
vim.opt.foldcolumn = '0'
-- Minimum lines for a fold to be created
vim.opt.foldminlines = 1

-- if performing an operation that would fail due to unsaved changes in the buffer (like `:q`),
-- instead raise a dialog asking if you wish to save the current file(s)
-- See `:help 'confirm'`
vim.opt.confirm = true

-- [[ Basic Keymaps ]]
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Folding keymaps
-- Use <leader>f for fold operations menu
vim.keymap.set('n', '<leader>ff', 'za', { desc = 'Toggle fold' })
vim.keymap.set('n', '<leader>fo', 'zo', { desc = 'Open fold' })
vim.keymap.set('n', '<leader>fc', 'zc', { desc = 'Close fold' })
vim.keymap.set('n', '<leader>fa', 'zA', { desc = 'Toggle all folds recursively' })
vim.keymap.set('n', '<leader>fO', 'zR', { desc = 'Open all folds' })
vim.keymap.set('n', '<leader>fC', 'zM', { desc = 'Close all folds' })
vim.keymap.set('n', '<leader>fr', 'zr', { desc = 'Reduce fold level' })
vim.keymap.set('n', '<leader>fm', 'zm', { desc = 'More folds (increase level)' })

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code [A]ction' })
vim.keymap.set('n', '<leader>cs', vim.diagnostic.open_float, { desc = '[C]urrent diagnostic [S]how' })

vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- [[ Filetype Detection ]]
vim.filetype.add({
  filename = {
    ['.env'] = 'sh',
  },
  pattern = {
    ['%.env%.[%w_.-]+'] = 'sh', -- .env.local, .env.development, etc.
  },
})

-- [[ Large File Handling ]]
-- Disable heavy features for large files to prevent stuttering
vim.g.large_file_size = 512 * 1024 -- 512KB
vim.g.large_file_line_length = 3000 -- lines longer than this

local large_file_group = vim.api.nvim_create_augroup('LargeFile', { clear = true })

-- Check file size BEFORE reading - disable stuff early
vim.api.nvim_create_autocmd('BufReadPre', {
  group = large_file_group,
  callback = function(args)
    local file = args.file
    local ok, stats = pcall(vim.uv.fs_stat, file)
    if ok and stats and stats.size > vim.g.large_file_size then
      vim.b[args.buf].large_file = true

      -- Disable these BEFORE the file loads
      vim.opt_local.eventignore:append({ 'FileType' }) -- prevent filetype plugins
      vim.bo[args.buf].buftype = 'nowrite' -- treat as special buffer initially
    end
  end,
})

-- After reading, apply full restrictions
vim.api.nvim_create_autocmd('BufReadPost', {
  group = large_file_group,
  callback = function(args)
    local buf = args.buf

    -- Check for long lines if not already marked
    if not vim.b[buf].large_file then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, 50, false)
      for _, line in ipairs(lines) do
        if #line > vim.g.large_file_line_length then
          vim.b[buf].large_file = true
          break
        end
      end
    end

    if vim.b[buf].large_file then
      vim.notify('Large file - minimal mode', vim.log.levels.WARN)

      -- Reset buftype so we can edit/save
      vim.bo[buf].buftype = ''
      vim.opt_local.eventignore = ''

      -- Kill ALL syntax/highlighting
      vim.cmd('syntax clear')
      vim.cmd('syntax off')
      vim.bo[buf].syntax = ''
      vim.bo[buf].filetype = ''
      pcall(vim.treesitter.stop, buf)

      -- Disable visual overhead
      vim.opt_local.cursorline = false
      vim.opt_local.cursorcolumn = false
      vim.opt_local.relativenumber = false
      vim.opt_local.number = false
      vim.opt_local.signcolumn = 'no'
      vim.opt_local.colorcolumn = ''
      vim.opt_local.list = false
      vim.opt_local.wrap = false

      -- Disable folding
      vim.opt_local.foldmethod = 'manual'
      vim.opt_local.foldenable = false

      -- Disable file features
      vim.opt_local.spell = false
      vim.opt_local.swapfile = false
      vim.opt_local.undofile = false
      vim.opt_local.undolevels = 100

      -- Disable matchparen (the highlight matching brackets plugin)
      vim.cmd('NoMatchParen')

      -- Detach LSP
      vim.schedule(function()
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
          vim.lsp.buf_detach_client(buf, client.id)
        end
      end)

      -- Detach gitsigns
      pcall(function() require('gitsigns').detach(buf) end)

      -- Disable indent-blankline
      pcall(function() require('ibl').setup_buffer(buf, { enabled = false }) end)

      -- Disable mini plugins for this buffer
      pcall(function() vim.b[buf].miniindentscope_disable = true end)
      pcall(function() vim.b[buf].minicursorword_disable = true end)
    end
  end,
})

-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

-- Ensure folding is set up properly for each buffer
vim.api.nvim_create_autocmd({'BufReadPost', 'FileReadPost'}, {
  pattern = '*',
  callback = function()
    vim.opt_local.foldmethod = 'indent'
    vim.opt_local.foldlevel = 99
  end,
})

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
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

-- Delete all buffers
vim.api.nvim_create_user_command('Bda', function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      vim.api.nvim_buf_delete(buf, { force = false })
    end
  end
end, { desc = 'Delete all buffers' })
vim.cmd('cnoreabbrev bda Bda')

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
-- vim.api.nvim_create_autocmd('CmdlineLeave', {
--   pattern = '*',
--   callback = function()
--     if vim.fn.getcmdline():match('^e!?$') then
--       vim.schedule(function()
--         local current_buf = vim.api.nvim_get_current_buf()
--         vim.cmd('bufdo e')
--         vim.api.nvim_set_current_buf(current_buf)
--       end)
--     end
--   end
-- })
