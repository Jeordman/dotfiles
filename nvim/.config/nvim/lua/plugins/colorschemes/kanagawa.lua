return {
  'rebelot/kanagawa.nvim',
  priority = 1000, -- Make sure to load this before all the other start plugins.
  config = function()
    -- Setup the theme
    require('kanagawa').setup {
      transparent = true,
      styles = {
        comments = { italic = false }, -- Disable italics in comments
      },
    }

    -- Load the colorscheme
    vim.cmd.colorscheme 'kanagawa' -- This applies the Kanagawa theme
  end,
}
