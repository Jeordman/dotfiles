return { -- code formatter
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format {
          async = true,
          lsp_fallback = 'always',
          range = vim.fn.mode() == 'v' and {
            start = vim.api.nvim_buf_get_mark(0, '<'),
            ['end'] = vim.api.nvim_buf_get_mark(0, '>'),
          } or nil,
        }
      end,
      mode = { 'n', 'v' },
      desc = '[F]ormat buffer or selection',
    },
  },
  opts = {
    notify_on_error = false,
    -- format_on_save = {
    --   timeout_ms = 500,
    --   lsp_fallback = true,
    --   stop_after_first = true,
    -- },
    formatters_by_ft = {
      lua = { 'stylua' },
      -- Use actual commands, not daemons, for consistency
      javascript = { 'eslint', 'prettier' },
      typescript = { 'eslint', 'prettier' },
      javascriptreact = { 'eslint', 'prettier' },
      typescriptreact = { 'eslint', 'prettier' },
      json = { 'prettier' },
      yaml = { 'prettier' },
      markdown = { 'prettier' },
      css = { 'prettier', 'stylelint' },
      scss = { 'prettier', 'stylelint' },
      less = { 'prettier', 'stylelint' },
      html = { 'prettier' },
    },
    formatters = {
      -- Configure ESLint to use --fix like your npm script
      eslint = {
        command = './node_modules/.bin/eslint',
        args = {
          '--fix',
          '--cache',
          '--format=json',
          '--stdin',
          '--stdin-filename',
          '$FILENAME',
        },
        stdin = true,
      },
      -- Configure Prettier to use project config
      prettier = {
        command = './node_modules/.bin/prettier',
        args = { '--write', '$FILENAME' },
        stdin = false,
        -- This ensures it uses your .prettierrc.cjs and plugins
      },
    },
  },
}
