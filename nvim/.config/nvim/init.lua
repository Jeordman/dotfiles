-- NOTE: REMERGED WITH KICKSTART.nvim May 8, 2025 --

require 'settings'

-- [[ Configure and install plugins ]]
--
--  To check the current status of your plugins, run
--    :Lazy
--
--  To update plugins you can run
--    :Lazy update
require('lazy').setup({
  require 'plugins.vim-sleuth',
  require 'plugins.git.gitsigns',
  require 'plugins.misc.which-key',
  require 'plugins.telescope',
  require 'plugins.lspconfig',
  require 'plugins.conform',
  require 'plugins.blink',
  -- require 'plugins.colorschemes.tokyonight',
  -- require 'plugins.colorschemes.rose-pine',
  -- require 'plugins.colorschemes.kanagawa',
  require 'plugins.colorschemes.catppuccin',
  require 'plugins.misc.todo-comments',
  require 'plugins.mini',
  require 'plugins.nvim-treesitter',
  require 'plugins.neo-tree',
  require 'plugins.lib.vim-visual-multi',
  require 'plugins.misc.indent-line',
  require 'plugins.git.fugitive',
  require 'plugins.lib.harpoon',
  -- require 'plugins.lib.copilot',
  require 'plugins.lib.supermaven',
  require 'plugins.lib.undotree',
  require 'plugins.lib.marks',
  require 'plugins.misc.line-numbers',
  require 'plugins.misc.lazygit',
  require 'plugins.misc.neoscroll',
  require 'plugins.misc.flash',
  require 'plugins.git.snacks',
}, {
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
