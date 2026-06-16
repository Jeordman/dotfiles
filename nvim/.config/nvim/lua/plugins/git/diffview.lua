-- ============================================================================
--  GIT REVIEW SYSTEM  (built on diffview.nvim)
-- ============================================================================
--  A consistent, repeatable ritual for reviewing changes — your own or AI's.
--  Same steps every time:
--
--    1. <leader>rr   Open the review   (uncommitted working tree vs HEAD)
--    2. <leader>rc   Open the checklist (map of every changed file + progress)
--    3. Walk the diff, file by file:
--         <Tab> / <S-Tab>   next / prev changed file
--         i                 toggle tree / flat view of the file panel
--         ]c / [c           next / prev hunk
--    4. Trace the logic — these work INSIDE the diff:
--         grd  go to definition     grr  references
--         K    signature / docs     <C-t>  jump back
--    5. <leader>rc again → tick off files as you finish them (x / <Space>)
--    6. <leader>rq   Close the review
--
--  PICK WHAT YOU'RE REVIEWING (the checklist follows the same base):
--    <leader>rr   uncommitted working tree vs HEAD   (about to commit the pile)
--    <leader>rm   vs main / master   (branch / PR delta — use this if your
--                                     AI changes are already COMMITTED)
--    <leader>rs   vs staging
--    <leader>rh   history of THIS file, commit by commit
--    <leader>rH   history of the whole branch, commit by commit
--
--  CHECKLIST KEYS:
--    x / <Space>  tick reviewed       <CR> / o  open file
--    h            hide / unhide row   H         reveal hidden rows
--    q / <Esc>    close
--    <leader>rx   clear ALL reviewed marks (start fresh; keeps hides)
--  Select multiple lines in VISUAL mode (V) to act on a range at once:
--    x / <Space>  mark all selected reviewed
--    h            hide all selected   H   unhide all selected
--
--  Reviewed marks persist in <git-dir>/nvim-review-checklist.json (see
--  lua/review_checklist.lua) and AUTO-EXPIRE when a file changes again — so
--  re-editing a file you'd ticked makes it show up unreviewed. Hidden files are
--  dropped from the list (a "N hidden" count stays visible; H reveals them).
--  Claude can tick OR hide files via the review-checklist skill — e.g. "narrow
--  the list to just what needs human eyes". Reopen <leader>rc to see its changes.
-- ============================================================================

local rc = require 'review_checklist'

local state = { mode = 'worktree' }

local function mode_label(mode)
  return ({
    worktree = 'working tree',
    main = 'vs ' .. rc.base_branch(),
    staging = 'vs origin/staging',
  })[mode] or mode
end

-- Floating checklist: a stable map of the whole change + a sense of progress.
local function open_checklist()
  local mode = state.mode
  local label = mode_label(mode)
  local show_hidden = false

  if #rc.compute(mode).files == 0 then
    vim.notify('Review: no changed files (' .. label .. ')', vim.log.levels.INFO)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  local ns = vim.api.nvim_create_namespace 'review_checklist'
  local rows = {} -- lnum -> { path, reviewed, hidden }

  local function render()
    local res = rc.compute(mode)
    local status = ('  %d / %d reviewed'):format(res.done, res.total)
    if res.hidden > 0 then
      status = status .. ('     %d hidden  ·  H to %s'):format(res.hidden, show_hidden and 'collapse' or 'show')
    end
    local lines = { '  Review checklist — ' .. label, status, '' }
    rows = {}
    for _, f in ipairs(res.files) do
      if (not f.hidden) or show_hidden then
        local mark = f.hidden and '~' or (f.reviewed and 'x' or ' ')
        table.insert(lines, ('- [%s] %-2s %s'):format(mark, f.status, f.path))
        rows[#lines] = { path = f.path, reviewed = f.reviewed, hidden = f.hidden }
      end
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { line_hl_group = 'Title' })
    vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { line_hl_group = 'Comment' })
    for lnum, row in pairs(rows) do
      if row.reviewed or row.hidden then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, { line_hl_group = 'Comment' })
      end
    end
  end

  render()

  local width = 50
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    width = math.max(width, #l + 4)
  end
  width = math.min(width, vim.o.columns - 8)
  local height = math.min(#vim.api.nvim_buf_get_lines(buf, 0, -1, false) + 1, vim.o.lines - 6)

  local prev_win = vim.api.nvim_get_current_win()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Review ',
    title_pos = 'center',
  })
  vim.wo[win].cursorline = true
  pcall(vim.api.nvim_win_set_cursor, win, { 4, 0 })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function restore_cursor(lnum)
    pcall(vim.api.nvim_win_set_cursor, win, { math.min(lnum, vim.api.nvim_buf_line_count(buf)), 0 })
  end

  local function toggle()
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    local row = rows[lnum]
    if not row then
      return
    end
    rc.toggle(row.path)
    render()
    restore_cursor(lnum)
  end

  local function toggle_hidden_row()
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    local row = rows[lnum]
    if not row then
      return
    end
    rc.toggle_hidden(row.path)
    render()
    restore_cursor(lnum)
  end

  local function toggle_show_hidden()
    show_hidden = not show_hidden
    render()
  end

  -- Apply one action to every file row in the current visual selection.
  local function visual_apply(action)
    local s, e = vim.fn.line 'v', vim.fn.line '.'
    if s > e then
      s, e = e, s
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    local paths = {}
    for lnum = s, e do
      if rows[lnum] then
        table.insert(paths, rows[lnum].path)
      end
    end
    if #paths > 0 then
      action(paths)
    end
    render()
    restore_cursor(s)
  end

  local function open_file()
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    local row = rows[lnum]
    if not row then
      return
    end
    close()
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(row.path))
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  -- Normal mode: act on the row under the cursor.
  vim.keymap.set('n', 'x', toggle, opts)
  vim.keymap.set('n', '<Space>', toggle, opts)
  vim.keymap.set('n', 'h', toggle_hidden_row, opts)
  vim.keymap.set('n', 'H', toggle_show_hidden, opts)
  vim.keymap.set('n', '<CR>', open_file, opts)
  vim.keymap.set('n', 'o', open_file, opts)
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
  -- Visual mode: act on every selected row at once.
  vim.keymap.set('x', 'x', function() visual_apply(function(p) rc.set_reviewed_many(p, true) end) end, opts)
  vim.keymap.set('x', '<Space>', function() visual_apply(function(p) rc.set_reviewed_many(p, true) end) end, opts)
  vim.keymap.set('x', 'h', function() visual_apply(function(p) rc.set_hidden_many(p, true) end) end, opts)
  vim.keymap.set('x', 'H', function() visual_apply(function(p) rc.set_hidden_many(p, false) end) end, opts)
end

local function clear_checklist()
  rc.clear()
  vim.notify 'Review: cleared all reviewed marks'
end

-- Entry points. They only set the base; reviewed marks are persisted by the
-- data layer and auto-expire on change, so opening a review never wipes them
-- (use <leader>rx to start fresh).
local function review_worktree()
  state.mode = 'worktree'
  vim.cmd 'DiffviewOpen'
end

local function review_main()
  state.mode = 'main'
  vim.cmd('DiffviewOpen ' .. rc.base_branch() .. '...HEAD')
end

local function review_staging()
  state.mode = 'staging'
  vim.cmd 'DiffviewOpen origin/staging...HEAD'
end

return {
  'sindrets/diffview.nvim',
  dependencies = 'nvim-lua/plenary.nvim',
  -- Register the commands so they lazy-load the plugin (fixes E492 when calling
  -- :DiffviewOpen before any diffview keymap has been pressed).
  cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewToggleFiles', 'DiffviewFocusFiles', 'DiffviewFileHistory' },
  opts = {
    -- view = {
    --   -- Stacked (old on top, new on bottom) instead of side-by-side, so each
    --   -- buffer gets the full window width — no truncated lines. Toggle live
    --   -- with g<C-x>.
    --   default = { layout = 'diff2_vertical' },
    --   file_history = { layout = 'diff2_vertical' },
    -- },
    file_panel = {
      listing_style = 'tree', -- see the shape of the change, not a flat wall of files
    },
    keymaps = {
      view = {
        { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Close diffview' } },
      },
      file_panel = {
        { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Close diffview' } },
      },
    },
  },
  keys = {
    -- Review namespace
    { '<leader>rr', review_worktree, desc = 'Review working tree (uncommitted)' },
    { '<leader>rm', review_main, desc = 'Review vs main/master' },
    { '<leader>rs', review_staging, desc = 'Review vs staging' },
    { '<leader>rh', '<Cmd>DiffviewFileHistory %<CR>', desc = 'Review history of this file' },
    { '<leader>rH', '<Cmd>DiffviewFileHistory<CR>', desc = 'Review history of branch' },
    { '<leader>rc', open_checklist, desc = 'Review checklist (changed files + progress)' },
    { '<leader>rf', '<Cmd>DiffviewToggleFiles<CR>', desc = 'Review files panel toggle' },
    { '<leader>rx', clear_checklist, desc = 'Review clear all marks' },
    { '<leader>rq', '<Cmd>DiffviewClose<CR>', desc = 'Review quit (close diffview)' },

    -- Legacy aliases (kept for muscle memory; route through the same functions)
    { '<leader>gm', review_main, desc = 'Git Review against main/master' },
    { '<leader>gss', review_staging, desc = 'Git Review against staging' },
  },
}
