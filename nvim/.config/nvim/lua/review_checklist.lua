-- ============================================================================
--  Review checklist — data layer
-- ============================================================================
--  Pure git + filesystem (no plugin deps) so it can be unit-tested headlessly
--  and shared with an external process.
--
--  State lives in <git-dir>/nvim-review-checklist.json:
--      { "version": 1,
--        "reviewed": { "rel/path.tsx": "<blob-hash>" },   -- ticked off
--        "hidden":   { "rel/path.tsx": true } }           -- removed from the list
--
--  A reviewed mark stores the git blob hash of the file's CURRENT working-tree
--  content. A file counts as reviewed only while that hash still matches, so
--  editing it again auto-expires the mark (like GitHub un-checking "viewed").
--
--  A hidden file is dropped from the checklist entirely (for noise the user — or
--  Claude, on request — decides isn't worth human eyes). nvim still shows a
--  "N hidden" count and can reveal/unhide them, so nothing vanishes silently.
--
--  Both sets are pruned to the current change-set on every read, so the file
--  never accumulates stale cruft. The companion `mark_reviewed.py`
--  (review-checklist skill) reads/writes the same file with the same rules.
-- ============================================================================

local M = {}

local SENTINEL_ABSENT = '<absent>' -- fingerprint for a deleted/missing file

local function syslist(cmd)
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return out
end

local function git_root()
  local out = syslist { 'git', 'rev-parse', '--show-toplevel' }
  if out and out[1] and out[1] ~= '' then
    return out[1]
  end
  return vim.fn.getcwd()
end

local function git_dir()
  local out = syslist { 'git', 'rev-parse', '--absolute-git-dir' }
  if out and out[1] and out[1] ~= '' then
    return out[1]
  end
  return git_root() .. '/.git'
end

local function state_path()
  return git_dir() .. '/nvim-review-checklist.json'
end

-- Blob hash of a path's current working-tree content (sentinel if it's gone).
local function fingerprint(root, path)
  if vim.fn.filereadable(root .. '/' .. path) == 0 then
    return SENTINEL_ABSENT
  end
  local out = syslist { 'git', '-C', root, 'hash-object', '--', path }
  if out and out[1] and out[1] ~= '' then
    return out[1]
  end
  return SENTINEL_ABSENT
end

-- Batched fingerprints { path -> hash }. Existing files hash in one git call;
-- missing files get the sentinel (git hash-object would error on them).
local function fingerprints(root, paths)
  local fps = {}
  local existing = {}
  for _, p in ipairs(paths) do
    if vim.fn.filereadable(root .. '/' .. p) == 1 then
      table.insert(existing, p)
    else
      fps[p] = SENTINEL_ABSENT
    end
  end
  if #existing > 0 then
    local cmd = { 'git', '-C', root, 'hash-object', '--' }
    vim.list_extend(cmd, existing)
    local out = syslist(cmd) or {}
    for i, p in ipairs(existing) do
      fps[p] = out[i] or SENTINEL_ABSENT
    end
  end
  return fps
end

function M.base_branch()
  local out = syslist { 'git', 'rev-parse', '--verify', 'origin/main' }
  return (out and out[1]) and 'origin/main' or 'origin/master'
end

-- Changed files for a review mode, in git's order: { { status, path }, ... }.
--   mode = 'worktree' (default) | 'main' | 'staging'
function M.changed_files(mode)
  local root = git_root()
  local files = {}
  if mode == 'main' or mode == 'staging' then
    local range = (mode == 'staging') and 'origin/staging...HEAD' or (M.base_branch() .. '...HEAD')
    for _, line in ipairs(syslist { 'git', '-C', root, 'diff', '--name-status', range } or {}) do
      local parts = vim.split(line, '\t', { plain = true })
      if #parts >= 2 then
        -- renames are "Rxx\told\tnew" — the current path is the last field
        table.insert(files, { status = parts[1]:sub(1, 1), path = parts[#parts] })
      end
    end
  else
    for _, line in ipairs(syslist { 'git', '-C', root, 'status', '--porcelain', '--untracked-files=all' } or {}) do
      if #line > 3 then
        local status = line:sub(1, 2)
        local path = line:sub(4)
        local arrow = path:find ' %-> '
        if arrow then
          path = path:sub(arrow + 4)
        end
        path = path:gsub('^"', ''):gsub('"$', '')
        table.insert(files, { status = (status:gsub('%s', '.')), path = path })
      end
    end
  end
  return files
end

local function load_state()
  local path = state_path()
  if vim.fn.filereadable(path) == 0 then
    return { reviewed = {}, hidden = {} }
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
  if not (ok and type(data) == 'table') then
    return { reviewed = {}, hidden = {} }
  end
  return {
    reviewed = type(data.reviewed) == 'table' and data.reviewed or {},
    hidden = type(data.hidden) == 'table' and data.hidden or {},
  }
end

local function save_state(st)
  -- vim.json.encode turns an empty table into "[]"; force objects so the Python
  -- side always sees JSON objects.
  local function obj(t)
    return next(t) == nil and '{}' or vim.json.encode(t)
  end
  local body = string.format('{"version":1,"reviewed":%s,"hidden":%s}', obj(st.reviewed or {}), obj(st.hidden or {}))
  local path = state_path()
  local tmp = path .. '.tmp'
  if vim.fn.writefile({ body }, tmp) == 0 then
    os.rename(tmp, path) -- atomic replace
  end
end

-- Compute the checklist for a mode, pruning stored marks/hides to the current,
-- still-relevant set as a side effect. Returns:
--   { files = { { status, path, reviewed, hidden }, ... },  -- ALL changed files
--     done, total,    -- counts over VISIBLE (non-hidden) files
--     hidden }         -- number of hidden files
function M.compute(mode)
  local root = git_root()
  local files = M.changed_files(mode)
  local paths = {}
  for _, f in ipairs(files) do
    table.insert(paths, f.path)
  end
  local fps = fingerprints(root, paths)
  local st = load_state()
  local pruned = { reviewed = {}, hidden = {} }
  local done, total, hidden = 0, 0, 0
  for _, f in ipairs(files) do
    f.reviewed = st.reviewed[f.path] ~= nil and st.reviewed[f.path] == fps[f.path]
    f.hidden = st.hidden[f.path] == true
    if f.reviewed then
      pruned.reviewed[f.path] = st.reviewed[f.path]
    end
    if f.hidden then
      pruned.hidden[f.path] = true
      hidden = hidden + 1
    else
      total = total + 1
      if f.reviewed then
        done = done + 1
      end
    end
  end
  save_state(pruned)
  return { files = files, done = done, total = total, hidden = hidden }
end

function M.toggle(path)
  local root = git_root()
  local st = load_state()
  local fp = fingerprint(root, path)
  if st.reviewed[path] ~= nil and st.reviewed[path] == fp then
    st.reviewed[path] = nil
  else
    st.reviewed[path] = fp
  end
  save_state(st)
end

function M.toggle_hidden(path)
  local st = load_state()
  st.hidden[path] = (st.hidden[path] == nil) and true or nil
  save_state(st)
end

-- Bulk setters (explicit on/off, not toggle) — for applying one action to a
-- whole visual selection in a single read/write.
function M.set_reviewed_many(paths, reviewed)
  local st = load_state()
  if reviewed then
    local fps = fingerprints(git_root(), paths)
    for _, p in ipairs(paths) do
      st.reviewed[p] = fps[p]
    end
  else
    for _, p in ipairs(paths) do
      st.reviewed[p] = nil
    end
  end
  save_state(st)
end

function M.set_hidden_many(paths, hidden)
  local st = load_state()
  for _, p in ipairs(paths) do
    st.hidden[p] = hidden and true or nil
  end
  save_state(st)
end

-- Clear reviewed marks (keeps hides). Use M.unhide_all() to bring hidden back.
function M.clear()
  local st = load_state()
  save_state { reviewed = {}, hidden = st.hidden }
end

function M.unhide_all()
  local st = load_state()
  save_state { reviewed = st.reviewed, hidden = {} }
end

return M
