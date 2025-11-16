-- Adds git-related signs to the gutter, as well as utilities for managing changes
return {
  'lewis6991/gitsigns.nvim',
  lazy = false,
  opts = {
    signs = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
    current_line_blame = true,
  },
  keys = {
    -- Select what to diff against
    {
      '<leader>gsd',
      function()
        vim.ui.select({ 'origin/staging', 'origin/master', 'index', 'HEAD' }, { prompt = 'Diff against:' },
          function(choice)
            if not choice then
              return
            end

            local base_map = {
              ['origin/staging'] = 'origin/staging', -- staging BRANCH
              ['origin/master'] = 'origin/master', -- master BRANCH
              ['index'] = nil,                     -- staging AREA
              HEAD = 'HEAD',
            }

            local base = base_map[choice]
            require('gitsigns').diffthis(base)
            print('Diffing against ' .. choice)
          end)
      end,
      desc = 'Choose diff base',
    },

    -- Navigation between hunks
    {
      ']c',
      function()
        require('gitsigns').next_hunk()
      end,
      desc = 'Next change',
    },
    {
      '[c',
      function()
        require('gitsigns').prev_hunk()
      end,
      desc = 'Previous change',
    },
  },
  config = function(_, opts)
    -- Setup Gitsigns with opts from above
    require('gitsigns').setup(opts)

    -- Any additional configuration can go here if needed
  end,
}
