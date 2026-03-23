---@class (exact) canola.git.Config
---@field enabled boolean
---@field show {untracked: boolean, ignored: boolean}
---@field format 'compact'|'porcelain'|'symbol'

---@class (exact) canola.git.CacheEntry
---@field ignored table<string, boolean>
---@field tracked table<string, boolean>
---@field status table<string, string>

---@class (exact) canola.git.StatusResult
---@field status string
---@field char string
---@field hl string
---@field index string?
---@field worktree string?

local M = {}

---@type table<string, canola.git.CacheEntry|false>
M._cache = {}
---@type table<string, true>
local pending = {}
---@type table<string, number>
local cache_time = {}
---@type table<string, any>
local watchers = {}
---@type table<string, any>
local debounce_timers = {}

---@type table<string, string>
local STAT_HL = {
  ['?'] = 'DiagnosticHint',
  ['!'] = 'Comment',
  ['A'] = 'DiagnosticOk',
  ['M'] = 'DiagnosticWarn',
  ['D'] = 'DiagnosticError',
  ['R'] = 'DiagnosticInfo',
  ['C'] = 'DiagnosticInfo',
  ['U'] = 'DiagnosticError',
}

---@type table<string, integer>
local STATUS_PRIORITY = {
  ['U'] = 6,
  ['D'] = 5,
  ['M'] = 4,
  ['R'] = 3,
  ['C'] = 3,
  ['A'] = 2,
  ['?'] = 1,
  ['!'] = 0,
}

---@return canola.git.Config
local function get_config()
  return vim.tbl_deep_extend('keep', vim.g.canola_git or {}, {
    enabled = true,
    show = { untracked = true, ignored = false },
    format = 'compact',
  })
end

---@param name string
---@return boolean
local function is_dotfile(name)
  return name:match('^%.') ~= nil
end

---@param xy string
---@return string
local function status_char(xy)
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  return x ~= ' ' and x or y
end

---@param xy string?
---@param fmt string
---@return string?
local function format_status(xy, fmt)
  if not xy then
    return nil
  end
  local c = status_char(xy)
  if c == ' ' then
    return nil
  end
  if fmt == 'porcelain' then
    return xy
  elseif fmt == 'symbol' then
    local syms = { ['M'] = '●', ['A'] = '+', ['D'] = '-', ['R'] = '»', ['?'] = '?', ['!'] = '!' }
    return syms[c] or c
  else
    return c
  end
end

---@param path string
---@return string
local function first_component(path)
  local slash = path:find('/', 1, true)
  return slash and path:sub(1, slash - 1) or path
end

---@param root string
local function start_watcher(root)
  if watchers[root] then
    return
  end
  local git_dir = root .. '/.git'
  local stat = vim.uv.fs_stat(git_dir)
  if not stat then
    return
  end
  local watch_path
  if stat.type == 'file' then
    local f = io.open(git_dir, 'r')
    if not f then
      return
    end
    local line = f:read('*l')
    f:close()
    local target = line and line:match('^gitdir: (.+)')
    if not target then
      return
    end
    if not target:match('^/') then
      target = root .. '/' .. target
    end
    watch_path = target
  else
    watch_path = git_dir
  end
  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end
  handle:start(
    watch_path,
    {},
    vim.schedule_wrap(function(err, filename)
      if err then
        return
      end
      if filename ~= 'index' and filename ~= 'HEAD' then
        return
      end
      if debounce_timers[root] then
        debounce_timers[root]:stop()
      end
      local timer = debounce_timers[root] or vim.uv.new_timer()
      if not timer then
        return
      end
      debounce_timers[root] = timer
      timer:start(
        300,
        0,
        vim.schedule_wrap(function()
          timer:stop()
          for _, winid in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(winid) then
              local bufnr = vim.api.nvim_win_get_buf(winid)
              if vim.bo[bufnr].filetype == 'canola' then
                M.invalidate()
                return
              end
            end
          end
        end)
      )
    end)
  )
  watchers[root] = handle
end

local function stop_watchers()
  for _, handle in pairs(watchers) do
    handle:stop()
    handle:close()
  end
  watchers = {}
  for _, timer in pairs(debounce_timers) do
    timer:stop()
    timer:close()
  end
  debounce_timers = {}
end

---@param dir string
local function populate_cache(dir)
  if pending[dir] then
    return
  end
  if not vim.uv.fs_stat(dir) then
    M._cache[dir] = false
    return
  end
  pending[dir] = true

  local git = require('canola.git')
  local root = git.get_root(dir)
  if not root then
    M._cache[dir] = false
    pending[dir] = nil
    return
  end
  pcall(start_watcher, root)
  local relprefix = dir:sub(#root + 1):gsub('^/', '')
  if relprefix ~= '' and relprefix:sub(-1) ~= '/' then
    relprefix = relprefix .. '/'
  end

  ---@type table<string, boolean>
  local ignored
  ---@type table<string, boolean>
  local tracked
  ---@type table<string, string>
  local status
  local remaining = 3

  local function on_query_done()
    remaining = remaining - 1
    if remaining > 0 then
      return
    end
    M._cache[dir] = { ignored = ignored, tracked = tracked, status = status }
    cache_time[dir] = vim.uv.now()
    pending[dir] = nil
    require('canola.view').rerender_all_oil_buffers({ refetch = false })
  end

  vim.system(
    { 'git', 'ls-files' },
    { cwd = dir, text = true },
    vim.schedule_wrap(function(result)
      tracked = {}
      if result.code == 0 then
        for _, line in ipairs(vim.split(result.stdout, '\n', { plain = true })) do
          if line ~= '' then
            tracked[first_component(line)] = true
          end
        end
      end
      on_query_done()
    end)
  )

  vim.system(
    { 'git', 'ls-files', '--ignored', '--exclude-standard', '--others', '--directory' },
    { cwd = dir, text = true },
    vim.schedule_wrap(function(result)
      ignored = {}
      if result.code == 0 then
        for _, line in ipairs(vim.split(result.stdout, '\n', { plain = true })) do
          local name = line:gsub('/$', '')
          if name ~= '' then
            ignored[name] = true
          end
        end
      end
      on_query_done()
    end)
  )

  vim.system(
    { 'git', 'status', '--porcelain', '--', '.' },
    { cwd = dir, text = true },
    vim.schedule_wrap(function(result)
      status = {}
      if result.code == 0 then
        for _, line in ipairs(vim.split(result.stdout, '\n', { plain = true })) do
          if #line >= 4 then
            local xy = line:sub(1, 2)
            local path = line:sub(4)
            local arrow = path:find(' -> ', 1, true)
            if arrow then
              path = path:sub(arrow + 4)
            end
            path = path:gsub('/$', '')
            if relprefix ~= '' and path:sub(1, #relprefix) == relprefix then
              path = path:sub(#relprefix + 1)
            end
            local name = first_component(path)
            if name ~= '' then
              local existing = status[name]
              if not existing then
                status[name] = xy
              else
                local new_pri = STATUS_PRIORITY[status_char(xy)] or 0
                local old_pri = STATUS_PRIORITY[status_char(existing)] or 0
                if new_pri > old_pri then
                  status[name] = xy
                end
              end
            end
          end
        end
      end
      on_query_done()
    end)
  )
end

---@param name string
---@param bufnr integer
---@return boolean
local function is_hidden(name, bufnr)
  if name == '..' then
    return false
  end

  local canola = require('canola')
  local dir = canola.get_current_dir(bufnr)
  if not dir then
    return is_dotfile(name)
  end

  local entry = M._cache[dir]
  if entry == nil then
    return is_dotfile(name)
  end

  if entry == false then
    return is_dotfile(name)
  end

  local show = get_config().show

  if is_dotfile(name) then
    return not entry.tracked[name]
  end

  if entry.ignored[name] then
    return not show.ignored
  end

  if not show.untracked and not entry.tracked[name] then
    return true
  end

  return false
end

M._init = function()
  require('canola.columns').register('git_status', {
    render = function(entry, conf, bufnr)
      local name = entry[require('canola.constants').FIELD_NAME]
      local dir = require('canola').get_current_dir(bufnr)
      if not dir then
        return nil
      end
      local cache = M._cache[dir]
      if not cache or cache == false or not cache.status then
        return nil
      end
      local xy = cache.status[name]
      local fmt = get_config().format
      local text = format_status(xy, fmt)
      if not text then
        return nil
      end
      if fmt == 'porcelain' then
        local x, y = xy:sub(1, 1), xy:sub(2, 2)
        local xhl = x ~= ' ' and (STAT_HL[x] or 'Normal') or 'Normal'
        local yhl = y ~= ' ' and (STAT_HL[y] or 'Normal') or 'Normal'
        return { text, { { xhl, 0, 1 }, { yhl, 1, 2 } } }
      end
      local c = status_char(xy)
      return { text, STAT_HL[c] or 'Normal' }
    end,
  })

  local cfg = get_config()
  if not cfg.enabled then
    return
  end

  require('canola').set_is_hidden_file(function(name, bufnr, _entry)
    return is_hidden(name, bufnr)
  end)

  vim.api.nvim_create_autocmd('User', {
    pattern = 'CanolaReadPost',
    callback = function(args)
      local bufnr = args.data.buf
      local canola = require('canola')
      local dir = canola.get_current_dir(bufnr)
      if not dir then
        return
      end
      if M._cache[dir] ~= nil then
        return
      end
      populate_cache(dir)
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'CanolaMutationComplete',
    callback = function()
      M.invalidate()
    end,
  })

  vim.api.nvim_create_autocmd({ 'FocusGained', 'ShellCmdPost' }, {
    callback = function()
      M.invalidate()
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    callback = function(args)
      if vim.bo[args.buf].filetype ~= 'canola' then
        return
      end
      local ok, dir = pcall(require('canola').get_current_dir, args.buf)
      if not ok or not dir then
        return
      end
      if pending[dir] then
        return
      end
      if cache_time[dir] and (vim.uv.now() - cache_time[dir]) < 2000 then
        return
      end
      M._cache[dir] = nil
      populate_cache(dir)
    end,
  })
end

---@param dir string
---@param name string
---@return canola.git.StatusResult?
M.get_status = function(dir, name)
  local cache = M._cache[dir]
  if not cache or cache == false or not cache.status then
    return nil
  end
  local xy = cache.status[name]
  if not xy then
    return nil
  end
  local c = status_char(xy)
  if c == ' ' then
    return nil
  end
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  return {
    status = xy,
    char = c,
    hl = STAT_HL[c] or 'Normal',
    index = x ~= ' ' and x or nil,
    worktree = y ~= ' ' and y or nil,
  }
end

M.invalidate = function()
  M._cache = {}
  cache_time = {}
  pending = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].filetype == 'canola' then
      local ok, dir = pcall(require('canola').get_current_dir, bufnr)
      if ok and dir then
        populate_cache(dir)
      end
    end
  end
end

M._stop_watchers = stop_watchers

return M
