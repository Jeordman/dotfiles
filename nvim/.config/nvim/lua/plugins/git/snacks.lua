-- must install gh cli
-- https://github.com/cli/cli#installation
-- brew install gh
-- gh auth login
return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  opts = {
    -- Disable features you don't need
    bigfile = { enabled = false },
    dashboard = { enabled = false },
    indent = { enabled = false },
    input = { enabled = false },
    notifier = { enabled = false },
    quickfile = { enabled = false },
    scroll = { enabled = false },
    statuscolumn = { enabled = false },
    words = { enabled = false },

    -- Enable git and gh features
    git = { enabled = true },
    gh = { enabled = true },
    picker = { enabled = true },
    lazygit = { enabled = true }, -- If you want lazygit integration
  },
  keys = {
    -- GitHub PR picker
    {
      '<leader>gr',
      function()
        Snacks.picker.gh_pr()
      end,
      desc = 'GitHub PRs for Review',
    },
    {
      '<leader>gD',
      function()
        vim.ui.input({ prompt = 'PR number: ' }, function(input)
          if input and input ~= '' then
            Snacks.picker.gh_diff { pr = tonumber(input) }
          end
        end)
      end,
      desc = 'View PR diff (enter number)',
    },

    -- -- Git diff view - this shows all changes in the current branch vs base
    -- {
    --   '<leader>gD',
    --   function()
    --     Snacks.git.diff()
    --   end,
    --   desc = 'Git Diff View',
    -- },
    -- {
    --   '<leader>gD',
    --   function()
    --     Snacks.picker.resume()
    --   end,
    --   desc = 'Resume last picker',
    -- },
  },
}
