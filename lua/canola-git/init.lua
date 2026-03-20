local M = {}

M._cache = {}
local pending = {}
local registered = false

local function get_config()
  return vim.tbl_extend('keep', vim.g.canola_git or {}, { enabled = true })
end

local function is_dotfile(name)
  return name:match('^%.') ~= nil
end

local function populate_cache(dir, bufnr)
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

  local function on_both_done()
    if ignored == nil or tracked == nil then
      return
    end
    M._cache[dir] = { ignored = ignored, tracked = tracked }
    pending[dir] = nil
    require('canola.view').rerender_all_oil_buffers({ refetch = false })
  end

  vim.system(
    { 'git', 'ls-files', '--ignored', '--exclude-standard', '--others', '--directory' },
    { cwd = dir, text = true },
    vim.schedule_wrap(function(result)
      local set = {}
      if result.code == 0 then
        for _, line in ipairs(vim.split(result.stdout, '\n', { plain = true })) do
          local name = line:gsub('/$', '')
          if name ~= '' then
            set[name] = true
          end
        end
      end
      ignored = set
      on_both_done()
    end)
  )

  vim.system(
    { 'git', 'ls-tree', 'HEAD', '--name-only' },
    { cwd = dir, text = true },
    vim.schedule_wrap(function(result)
      local set = {}
      if result.code == 0 then
        for _, line in ipairs(vim.split(result.stdout, '\n', { plain = true })) do
          if line ~= '' then
            set[line] = true
          end
        end
      end
      tracked = set
      on_both_done()
    end)
  )
end

local function is_hidden(name, bufnr)
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

  if is_dotfile(name) then
    return not entry.tracked[name]
  else
    return entry.ignored[name] == true
  end
end

M.setup = function()
  if registered then
    return
  end
  registered = true

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
      M._cache[dir] = nil
      populate_cache(dir, bufnr)
    end,
  })
end

return M
