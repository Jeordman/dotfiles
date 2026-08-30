return {
  { -- Add indentation guides even on blank lines
    'lukas-reineke/indent-blankline.nvim',
    -- BufReadPre rather than BufReadPost so ibl is already loaded by the time
    -- the large-file handler in settings.lua calls ibl.setup_buffer() to turn
    -- the guides off for that buffer.
    -- See `:help ibl`
    event = { 'BufReadPre', 'BufNewFile' },
    main = 'ibl',
    opts = {},
  },
}
