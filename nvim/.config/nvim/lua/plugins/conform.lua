-- Detect project tooling to choose formatters
local prettier_configs = {
  '.prettierrc',
  '.prettierrc.json',
  '.prettierrc.js',
  '.prettierrc.cjs',
  '.prettierrc.mjs',
  '.prettierrc.yml',
  '.prettierrc.yaml',
  '.prettierrc.toml',
  'prettier.config.js',
  'prettier.config.cjs',
  'prettier.config.mjs',
}

local eslint_configs = {
  '.eslintrc',
  '.eslintrc.js',
  '.eslintrc.cjs',
  '.eslintrc.json',
  '.eslintrc.yml',
  '.eslintrc.yaml',
  'eslint.config.js',
  'eslint.config.cjs',
  'eslint.config.mjs',
  'eslint.config.ts',
}

local function has_config(ctx, patterns)
  return vim.fs.find(patterns, { upward = true, path = ctx.dirname })[1] ~= nil
end

return { -- code formatter
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        local conform = require 'conform'
        local formatters = conform.list_formatters(0)
        local names = vim.tbl_map(function(f) return f.name end, formatters)
        local range = vim.fn.mode() == 'v' and {
          start = vim.api.nvim_buf_get_mark(0, '<'),
          ['end'] = vim.api.nvim_buf_get_mark(0, '>'),
        } or nil
        conform.format({ async = true, lsp_fallback = 'always', range = range }, function(err)
          vim.schedule(function()
            if err then return end
            if #names > 0 then
              vim.notify('Formatted with ' .. table.concat(names, ', '))
            else
              vim.notify('Formatted with LSP')
            end
          end)
        end)
      end,
      mode = { 'n', 'v' },
      desc = '[F]ormat buffer or selection',
    },
  },
  opts = {
    notify_on_error = true,
    -- format_on_save = {
    --   timeout_ms = 500,
    --   lsp_fallback = true,
    --   stop_after_first = true,
    -- },
    formatters_by_ft = {
      lua = { 'stylua' },
      javascript = { 'eslint', 'prettier', 'biome' },
      typescript = { 'eslint', 'prettier', 'biome' },
      javascriptreact = { 'eslint', 'prettier', 'biome' },
      typescriptreact = { 'eslint', 'prettier', 'biome' },
      json = { 'prettier', 'biome' },
      yaml = { 'prettier' },
      markdown = { 'prettier' },
      css = { 'prettier', 'biome', 'stylelint' },
      scss = { 'prettier', 'stylelint' },
      less = { 'prettier', 'stylelint' },
      html = { 'prettier' },
    },
    formatters = {
      eslint = {
        condition = function(self, ctx)
          return has_config(ctx, eslint_configs)
        end,
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
      prettier = {
        condition = function(self, ctx)
          return has_config(ctx, prettier_configs)
        end,
        command = './node_modules/.bin/prettier',
        args = { '--write', '$FILENAME' },
        stdin = false,
      },
      biome = {
        condition = function(self, ctx)
          return not has_config(ctx, prettier_configs) and not has_config(ctx, eslint_configs)
        end,
      },
    },
  },
}
