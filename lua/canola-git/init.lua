local M = {}

M._cache = {}
local pending = {}

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

local function get_config()
  return vim.tbl_deep_extend('keep', vim.g.canola_git or {}, {
    enabled = true,
    show = { untracked = true, ignored = false },
    format = 'compact',
  })
end

local function is_dotfile(name)
  return name:match('^%.') ~= nil
end

local function status_char(xy)
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  return x ~= ' ' and x or y
end

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

local function first_component(path)
  local slash = path:find('/', 1, true)
  return slash and path:sub(1, slash - 1) or path
end

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

  local ignored = nil
  local tracked = nil
  local status = nil
  local remaining = 3

  local function on_query_done()
    remaining = remaining - 1
    if remaining > 0 then
      return
    end
    M._cache[dir] = { ignored = ignored, tracked = tracked, status = status }
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
      local text = format_status(xy, get_config().format)
      if not text then
        return nil
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
      M._cache[dir] = nil
      populate_cache(dir)
    end,
  })
end

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
  return {
    status = xy,
    char = c,
    hl = STAT_HL[c] or 'Normal',
  }
end

M.invalidate = function()
  M._cache = {}
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

return M
