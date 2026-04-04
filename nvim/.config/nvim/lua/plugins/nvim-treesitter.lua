return { -- Highlight, edit, and navigate code
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  build = ':TSUpdate',
  -- [[ Configure Treesitter ]] See `:help nvim-treesitter`
  opts = {
    ensure_installed = {
      'bash',
      'c',
      'diff',
      'html',
      'lua',
      'luadoc',
      'markdown',
      'markdown_inline',
      'query',
      'vim',
      'vimdoc',
      'typescript', -- TypeScript files (.ts)
      'tsx',        -- React/Next.js (.tsx)
      'javascript', -- JavaScript files (.js)
      'jsdoc',      -- JSDoc comments
      'json',       -- package.json, tsconfig.json
      'css',        -- CSS files
      'scss',       -- SCSS (if you use it)
      'php',        -- PHP files
      'phpdoc',     -- PHPDoc comments
      'sql',        -- SQL
      'toml',       -- TOML configuration files
    },
    -- Autoinstall languages that are not installed
    auto_install = true,
  },
  config = function(_, opts)
    require('nvim-treesitter').setup(opts)

    -- Enable treesitter highlighting for all languages except markdown
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        local ft = vim.bo[args.buf].filetype
        if ft ~= 'markdown' then
          pcall(vim.treesitter.start, args.buf)
        end
      end,
    })

    -- Enable treesitter-based indentation (except ruby)
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        local ft = vim.bo[args.buf].filetype
        if ft ~= 'ruby' then
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })
  end,
  -- There are additional nvim-treesitter modules that you can use to interact
  -- with nvim-treesitter. You should go explore a few and see what interests you:
  --
  --    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
  --    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
  --    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
}
