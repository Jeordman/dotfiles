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
    numhl = true,      -- tint the line number for changed lines
    linehl = true,     -- full-line fill: green = added, amber = modified
    word_diff = false, -- off: avoids a second highlight stacking on the line fill
    current_line_blame = true,
  },
  keys = {
    -- Select what to diff against
    {
      '<leader>gf',
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
      desc = 'Git Review file',
    },

    -- Toggle the loud inline-diff highlighting (line bg + word diff) on/off
    {
      '<leader>gh',
      function()
        vim.cmd('Gitsigns toggle_linehl')
        vim.cmd('Gitsigns toggle_word_diff')
        vim.cmd('Gitsigns toggle_numhl')
      end,
      desc = 'Toggle git inline-diff highlight',
    },
    -- Show deleted lines inline as virtual text
    {
      '<leader>gD',
      function()
        vim.cmd('Gitsigns toggle_deleted')
      end,
      desc = 'Toggle show deleted lines',
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

    -- Force clearly-distinct, saturated diff highlights (green = added,
    -- amber = modified, red = deleted) so they read even over a translucent
    -- terminal background. Re-applied on ColorScheme so a theme switch can't
    -- wipe them.
    local function set_diff_hl()
      -- Full-line fills tuned for a muted, low-contrast dark theme:
      -- green = added, slate-blue = modified, red = deleted. Modified is the
      -- most common line, so it's the calmest/coolest tone (recedes, never
      -- blows out) while green/red stay as-is.
      vim.api.nvim_set_hl(0, 'GitSignsAddLn', { bg = '#14301c' })
      vim.api.nvim_set_hl(0, 'GitSignsChangeLn', { bg = '#1b2738' })
      vim.api.nvim_set_hl(0, 'GitSignsDeleteLn', { bg = '#341515' })
      -- Inline word-diff (only shown if word_diff is toggled back on).
      vim.api.nvim_set_hl(0, 'GitSignsAddInline', { bg = '#235232' })
      vim.api.nvim_set_hl(0, 'GitSignsChangeInline', { bg = '#2d4660' })
      vim.api.nvim_set_hl(0, 'GitSignsDeleteInline', { bg = '#5a1f28' })
    end

    set_diff_hl()
    vim.api.nvim_create_autocmd('ColorScheme', {
      callback = set_diff_hl,
      desc = 'Reapply Gitsigns diff highlights',
    })
  end,
}
