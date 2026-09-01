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
      enable_git_status = true,
      git_status_async = true,
      window = {
        position = 'right',
        width = 40,
        -- Expand the window so the current file name is fully visible
        auto_expand_width = true,
        mappings = {
          ['/'] = 'noop',
        },
      },
      filesystem = {
        window = {
          mappings = {
            -- jump between git-changed entries with ]c / [c instead of ]g / [g
            ['[g'] = 'noop',
            [']g'] = 'noop',
            ['[c'] = 'prev_git_modified',
            [']c'] = 'next_git_modified',
          },
        },
      },
      default_component_configs = {
        -- color the file NAME by git status, not just the trailing symbol
        name = {
          use_git_status_colors = true,
        },
        git_status = {
          symbols = {
            added     = '+',
            modified  = '~',
            deleted   = '_',
            renamed   = '→',
            untracked = '?',
            ignored   = '',
            unstaged  = '',
            staged    = '●',
            conflict  = '!',
          },
        },
      },
    }

    -- Every file name is white. Git status recolors the text only, no
    -- backgrounds: blue = modified, green = added/untracked, red = deleted.
    -- Reapplied on ColorScheme so a theme switch can't wipe them.
    local white = '#c6c1a9'
    local blue = '#7aa2f7'
    local green = '#a6e3a1'
    local red = '#D95F5F'
    -- Matches herdr's sidebar_bg so the tree reads as chrome, not buffer.
    local sidebar_bg = '#161616'

    local function set_neotree_git_hl()
      vim.api.nvim_set_hl(0, 'NeoTreeNormal', { fg = white, bg = sidebar_bg })
      vim.api.nvim_set_hl(0, 'NeoTreeNormalNC', { fg = white, bg = sidebar_bg })
      vim.api.nvim_set_hl(0, 'NeoTreeEndOfBuffer', { fg = sidebar_bg, bg = sidebar_bg })
      vim.api.nvim_set_hl(0, 'NeoTreeWinSeparator', { fg = sidebar_bg, bg = sidebar_bg })
      vim.api.nvim_set_hl(0, 'NeoTreeCursorLine', { bg = '#242424' })

      vim.api.nvim_set_hl(0, 'NeoTreeFileName', { fg = white })
      vim.api.nvim_set_hl(0, 'NeoTreeFileNameOpened', { fg = white })
      vim.api.nvim_set_hl(0, 'NeoTreeDirectoryName', { fg = white })
      vim.api.nvim_set_hl(0, 'NeoTreeDirectoryIcon', { fg = white })
      vim.api.nvim_set_hl(0, 'NeoTreeRootName', { fg = white, bold = true })

      vim.api.nvim_set_hl(0, 'NeoTreeGitAdded', { fg = green })
      vim.api.nvim_set_hl(0, 'NeoTreeGitStaged', { fg = green })
      vim.api.nvim_set_hl(0, 'NeoTreeGitUntracked', { fg = green })
      vim.api.nvim_set_hl(0, 'NeoTreeGitModified', { fg = blue })
      vim.api.nvim_set_hl(0, 'NeoTreeGitUnstaged', { fg = blue })
      vim.api.nvim_set_hl(0, 'NeoTreeGitRenamed', { fg = blue })
      vim.api.nvim_set_hl(0, 'NeoTreeGitDeleted', { fg = red })
      vim.api.nvim_set_hl(0, 'NeoTreeGitConflict', { fg = red, bold = true })
    end

    set_neotree_git_hl()
    vim.api.nvim_create_autocmd('ColorScheme', {
      callback = set_neotree_git_hl,
      desc = 'Reapply Neo-tree git highlights',
    })
  end,
}
