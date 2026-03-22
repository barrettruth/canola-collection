local cache = require('canola.cache')
local config = require('canola.config')
local files = require('canola.adapters.files')
local fs = require('canola.fs')
local util = require('canola.util')

local uv = vim.uv or vim.loop

local M = {}

---@param path string
local function touch_dir(path)
  uv.fs_mkdir(path, 448) -- 0700
end

---Gets the location of the home trash dir, creating it if necessary
---@return string
local function get_trash_dir()
  local trash_dir = fs.join(assert(uv.os_homedir()), '.Trash')
  touch_dir(trash_dir)
  return trash_dir
end

---@return string
local function get_info_dir()
  local info_dir = fs.join(get_trash_dir(), '.canola-info')
  touch_dir(info_dir)
  return info_dir
end

---@param url string
---@param callback fun(url: string)
M.normalize_url = function(url, callback)
  local scheme, path = util.parse_url(url)
  assert(path)
  local os_path = vim.fn.fnamemodify(fs.posix_to_os_path(path), ':p')
  uv.fs_realpath(
    os_path,
    vim.schedule_wrap(function(_err, new_os_path)
      local realpath = new_os_path or os_path
      callback(scheme .. util.addslash(fs.os_to_posix_path(realpath)))
    end)
  )
end

---@param url string
---@param entry canola.Entry
---@param cb fun(path: string)
M.get_entry_path = function(url, entry, cb)
  local trash_dir = get_trash_dir()
  local path = fs.join(trash_dir, entry.name)
  if entry.type == 'directory' then
    path = 'canola://' .. path
  end
  cb(path)
end

---@param url string
---@param column_defs string[]
---@param cb fun(err?: string, entries?: canola.InternalEntry[], fetch_more?: fun())
M.list = function(url, column_defs, cb)
  cb = vim.schedule_wrap(cb)
  local _, path = util.parse_url(url)
  assert(path)
  local trash_dir = get_trash_dir()
  local info_dir = get_info_dir()
  ---@diagnostic disable-next-line: param-type-mismatch, discard-returns
  uv.fs_opendir(trash_dir, function(open_err, fd)
    if open_err then
      if open_err:match('^ENOENT: no such file or directory') then
        return cb()
      else
        return cb(open_err)
      end
    end
    local read_next
    read_next = function()
      uv.fs_readdir(fd, function(err, entries)
        if err then
          uv.fs_closedir(fd, function()
            cb(err)
          end)
          return
        elseif entries then
          local internal_entries = {}
          local poll = util.cb_collect(#entries, function(inner_err)
            if inner_err then
              cb(inner_err)
            else
              cb(nil, internal_entries, read_next)
            end
          end)

          for _, entry in ipairs(entries) do
            if entry.name:match('%.trashinfo$') or entry.name == '.canola-info' then
              poll()
              goto continue
            end

            do
              local sidecar = fs.join(info_dir, entry.name .. '.trashinfo')
              local original_path = nil
              local f = io.open(sidecar, 'r')
              if f then
                for line in f:lines() do
                  local p = line:match('^Path=(.+)$')
                  if p then
                    original_path = p
                    break
                  end
                end
                f:close()
              end

              local show = (path == '/' or original_path == nil)
              if not show and original_path then
                local parent = util.addslash(vim.fn.fnamemodify(original_path, ':h'))
                show = (fs.os_to_posix_path(parent) == path)
              end

              if show then
                local cache_entry = cache.create_entry(url, entry.name, entry.type)
                table.insert(internal_entries, cache_entry)
              end
            end
            poll()
            ::continue::
          end
        else
          uv.fs_closedir(fd, function(close_err)
            if close_err then
              cb(close_err)
            else
              cb()
            end
          end)
        end
      end)
    end
    read_next()
    ---@diagnostic disable-next-line: param-type-mismatch
  end, 10000)
end

---@param bufnr integer
---@return boolean
M.is_modifiable = function(bufnr)
  return true
end

---@param name string
---@return nil|canola.ColumnDefinition
M.get_column = function(name)
  return nil
end

---@type table<string, string>
M.supported_cross_adapter_actions = { files = 'move' }

---@param action canola.Action
---@return string
M.render_action = function(action)
  if action.type == 'create' then
    return string.format('CREATE %s', action.url)
  elseif action.type == 'delete' then
    return string.format(' PURGE %s', action.url)
  elseif action.type == 'move' then
    local src_adapter = assert(config.get_adapter_by_scheme(action.src_url))
    local dest_adapter = assert(config.get_adapter_by_scheme(action.dest_url))
    if src_adapter.name == 'files' then
      local _, path = util.parse_url(action.src_url)
      assert(path)
      local short_path = files.to_short_os_path(path, action.entry_type)
      return string.format(' TRASH %s', short_path)
    elseif dest_adapter.name == 'files' then
      local _, path = util.parse_url(action.dest_url)
      assert(path)
      local short_path = files.to_short_os_path(path, action.entry_type)
      return string.format('RESTORE %s', short_path)
    else
      return string.format('  %s %s -> %s', action.type:upper(), action.src_url, action.dest_url)
    end
  elseif action.type == 'copy' then
    return string.format('  %s %s -> %s', action.type:upper(), action.src_url, action.dest_url)
  else
    error('Bad action type')
  end
end

---@param action canola.Action
---@param cb fun(err: nil|string)
M.perform_action = function(action, cb)
  local trash_dir = get_trash_dir()
  if action.type == 'create' then
    local _, path = util.parse_url(action.url)
    assert(path)
    path = trash_dir .. path
    if action.entry_type == 'directory' then
      uv.fs_mkdir(path, 493, function(err)
        -- Ignore if the directory already exists
        if not err or err:match('^EEXIST:') then
          cb()
        else
          cb(err)
        end
      end) -- 0755
    elseif action.entry_type == 'link' and action.link then
      local flags = nil
      local target = fs.posix_to_os_path(action.link)
      ---@diagnostic disable-next-line: param-type-mismatch
      uv.fs_symlink(target, path, flags, cb)
    else
      fs.touch(path, config.create.file_mode, cb)
    end
  elseif action.type == 'delete' then
    local _, path = util.parse_url(action.url)
    assert(path)
    local fullpath = trash_dir .. path
    fs.recursive_delete(action.entry_type, fullpath, cb)
  elseif action.type == 'move' or action.type == 'copy' then
    local src_adapter = assert(config.get_adapter_by_scheme(action.src_url))
    local dest_adapter = assert(config.get_adapter_by_scheme(action.dest_url))
    local _, src_path = util.parse_url(action.src_url)
    local _, dest_path = util.parse_url(action.dest_url)
    assert(src_path and dest_path)
    if src_adapter.name == 'files' then
      dest_path = trash_dir .. dest_path
    elseif dest_adapter.name == 'files' then
      src_path = trash_dir .. src_path
    else
      dest_path = trash_dir .. dest_path
      src_path = trash_dir .. src_path
    end

    if action.type == 'move' then
      fs.recursive_move(action.entry_type, src_path, dest_path, cb)
    else
      fs.recursive_copy(action.entry_type, src_path, dest_path, cb)
    end
  else
    cb(string.format('Bad action type: %s', action.type))
  end
end

---@param path string
---@param cb fun(err?: string)
M.delete_to_trash = function(path, cb)
  local basename = vim.fs.basename(path)
  local trash_dir = get_trash_dir()
  local dest = fs.join(trash_dir, basename)
  uv.fs_lstat(
    path,
    vim.schedule_wrap(function(stat_err, src_stat)
      if stat_err then
        return cb(stat_err)
      end
      assert(src_stat)
      if uv.fs_lstat(dest) then
        local date_str = vim.fn.strftime(' %Y-%m-%dT%H:%M:%S')
        local name_pieces = vim.split(basename, '.', { plain = true })
        if #name_pieces > 1 then
          table.insert(name_pieces, #name_pieces - 1, date_str)
          basename = table.concat(name_pieces)
        else
          basename = basename .. date_str
        end
        dest = fs.join(trash_dir, basename)
      end

      local sidecar = fs.join(get_info_dir(), basename .. '.trashinfo')
      local deletion_date = vim.fn.strftime('%Y-%m-%dT%H:%M:%S')
      local contents = string.format('[Trash Info]\nPath=%s\nDeletionDate=%s', path, deletion_date)
      uv.fs_open(sidecar, 'w', 448, function(open_err, fd)
        if not open_err and fd then
          uv.fs_write(fd, contents, function()
            uv.fs_close(fd)
          end)
        end
      end)

      local stat_type = src_stat.type
      fs.recursive_move(stat_type, path, dest, vim.schedule_wrap(cb))
    end)
  )
end

return M
