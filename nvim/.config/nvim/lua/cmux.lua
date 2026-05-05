-- cmux markdown viewer integration.
-- :Md [path] opens the file in cmux's markdown viewer as a TAB inside the
-- current pane (instead of a side split). No autocmds — manual only.

if vim.fn.executable('cmux') == 0 then
  return
end

local function open_as_tab(path)
  if not path or path == '' then
    vim.notify('cmux: no path', vim.log.levels.WARN)
    return
  end
  path = vim.fn.fnamemodify(path, ':p')
  if vim.fn.filereadable(path) == 0 then
    vim.notify('cmux: file not readable: ' .. path, vim.log.levels.WARN)
    return
  end

  -- Find the pane vim is sitting in.
  local id = vim.system({ 'cmux', 'identify' }, { text = true }):wait()
  if id.code ~= 0 then
    vim.notify('cmux identify failed: ' .. (id.stderr or ''), vim.log.levels.ERROR)
    return
  end
  local ok, info = pcall(vim.json.decode, id.stdout)
  if not ok or not info or not info.caller or not info.caller.pane_ref then
    vim.notify('cmux: could not resolve current pane', vim.log.levels.ERROR)
    return
  end
  local target_pane = info.caller.pane_ref

  -- Open viewer (creates a split pane with one surface).
  local md = vim.system(
    { 'cmux', 'markdown', 'open', path, '--focus', 'false' },
    { text = true }
  ):wait()
  if md.code ~= 0 then
    vim.notify('cmux markdown failed: ' .. (md.stderr or md.stdout or ''), vim.log.levels.ERROR)
    return
  end
  local new_surface = (md.stdout or ''):match('surface=(surface:%d+)')
  if not new_surface then
    vim.notify('cmux: could not parse surface from output', vim.log.levels.ERROR)
    return
  end

  -- Move the new viewer surface into vim's pane → becomes a sibling tab.
  vim.system(
    { 'cmux', 'move-surface', '--surface', new_surface, '--pane', target_pane, '--focus', 'true' },
    { text = true }
  )
end

vim.api.nvim_create_user_command('Md', function(opts)
  local path = opts.args ~= '' and opts.args or vim.fn.expand('%:p')
  open_as_tab(path)
end, { nargs = '?', complete = 'file', desc = 'Open file in cmux markdown viewer (as tab)' })

vim.keymap.set('n', '<leader>md', function()
  open_as_tab(vim.fn.expand('%:p'))
end, { desc = '[M]arkdown: open in cmux viewer tab' })
