local M = {}

M._cache = {}
local pending = {}
local registered = false

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

local function needs_status_column()
  local cols = (vim.g.canola or {}).columns or {}
  for _, col in ipairs(cols) do
    local name = type(col) == 'table' and col[1] or col
    if name == 'git_status' then
      return true
    end
  end
  return false
end

local function format_status(xy, fmt)
  if not xy then
    return nil
  end
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  local c = x ~= ' ' and x or y
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

local function populate_cache(dir)
  if pending[dir] then
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
  local with_status = needs_status_column()
  local remaining = with_status and 3 or 2

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
    { 'git', 'ls-tree', 'HEAD', '--name-only' },
    { cwd = dir, text = true },
    vim.schedule_wrap(function(result)
      tracked = {}
      if result.code == 0 then
        for _, line in ipairs(vim.split(result.stdout, '\n', { plain = true })) do
          if line ~= '' then
            tracked[line] = true
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

  if with_status then
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
              local slash = path:find('/', 1, true)
              local name = slash and path:sub(1, slash - 1) or path
              if name ~= '' and not status[name] then
                status[name] = xy
              end
            end
          end
        end
        on_query_done()
      end)
    )
  end
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

M.setup = function()
  if registered then
    return
  end
  registered = true

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
      local c = xy:sub(1, 1) ~= ' ' and xy:sub(1, 1) or xy:sub(2, 2)
      return { text, STAT_HL[c] or 'Normal' }
    end,
    parse = function(line, conf)
      return line:match('^(%S+)%s+(.*)$')
    end,
  })

  local cfg = get_config()
  if not cfg.enabled then
    return
  end

  vim.schedule(function()
    require('canola').set_is_hidden_file(function(name, bufnr, _entry)
      return is_hidden(name, bufnr)
    end)
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
end

return M
