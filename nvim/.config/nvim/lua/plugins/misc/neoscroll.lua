return {
  'karb94/neoscroll.nvim',
  event = 'VeryLazy',
  opts = {
    easing = 'sine',
    duration = 100,
    -- Default list includes <C-f>, and neoscroll loads on VeryLazy (after
    -- telescope's VimEnter config), so it silently clobbered <C-f> = live_grep.
    -- Everything below is the upstream default minus <C-f>.
    mappings = { '<C-u>', '<C-d>', '<C-b>', '<C-y>', '<C-e>', 'zt', 'zz', 'zb' },
  },
}
