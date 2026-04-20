local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
  .. '/plugin/canola-collection.lua'

local function parse_url(url)
  return url:match('^(.-://)(.*)$')
end

local function clear_state()
  package.loaded['canola'] = nil
  package.loaded['canola-git'] = nil
  package.loaded['canola.adapters.files'] = nil
  package.loaded['canola.adapters.trash'] = nil
  package.loaded['canola.fs'] = nil
  package.loaded['canola.util'] = nil
  vim.g.canola = nil
  vim.g.canola_git = nil
  vim.g.canola_ssh = nil
  vim.g.canola_s3 = nil
  vim.g.canola_ftp = nil
  vim.g.canola_trash = nil
end

local function has_registration(calls, scheme, name)
  for _, call in ipairs(calls) do
    if call.scheme == scheme and call.name == name then
      return true
    end
  end
  return false
end

describe('plugin/canola-collection.lua', function()
  local register_calls
  local autocmds
  local git_init_calls
  local trash_deletes
  local files
  local original_create_autocmd

  before_each(function()
    clear_state()
    register_calls = {}
    autocmds = {}
    git_init_calls = 0
    trash_deletes = {}
    files = {
      perform_action = function(_action, cb)
        cb('orig')
      end,
      render_action = function(_action)
        return 'orig'
      end,
      to_short_os_path = function(path, _entry_type)
        return path
      end,
    }
    package.loaded['canola'] = {
      register_adapter = function(scheme, name)
        table.insert(register_calls, { scheme = scheme, name = name })
      end,
    }
    package.loaded['canola-git'] = {
      _init = function()
        git_init_calls = git_init_calls + 1
      end,
    }
    package.loaded['canola.adapters.files'] = files
    package.loaded['canola.adapters.trash'] = {
      delete_to_trash = function(path, cb)
        table.insert(trash_deletes, path)
        cb()
      end,
    }
    package.loaded['canola.fs'] = {
      posix_to_os_path = function(path)
        return path
      end,
    }
    package.loaded['canola.util'] = {
      parse_url = parse_url,
    }
    original_create_autocmd = vim.api.nvim_create_autocmd
    vim.api.nvim_create_autocmd = function(event, opts)
      table.insert(autocmds, { event = event, opts = opts })
      return #autocmds
    end
  end)

  after_each(function()
    vim.api.nvim_create_autocmd = original_create_autocmd
    clear_state()
  end)

  it('does not activate any feature by default', function()
    local orig_perform = files.perform_action
    local orig_render = files.render_action
    dofile(plugin_path)
    assert.are.same({}, register_calls)
    assert.are.same({}, autocmds)
    assert.equals(0, git_init_calls)
    assert.equals(orig_perform, files.perform_action)
    assert.equals(orig_render, files.render_action)
  end)

  it('treats an empty ssh table as enabled', function()
    vim.g.canola_ssh = {}
    dofile(plugin_path)
    assert.is_true(has_registration(register_calls, 'canola-ssh://', 'ssh'))
    assert.equals('BufNew', autocmds[1].event)
    assert.equals('scp://*', autocmds[1].opts.pattern)
  end)

  it('treats an empty s3 table as enabled', function()
    vim.g.canola_s3 = {}
    dofile(plugin_path)
    assert.is_true(has_registration(register_calls, 'canola-s3://', 's3'))
  end)

  it('treats an empty ftp table as enabled', function()
    vim.g.canola_ftp = {}
    dofile(plugin_path)
    assert.is_true(has_registration(register_calls, 'canola-ftp://', 'ftp'))
    assert.is_true(has_registration(register_calls, 'canola-ftps://', 'ftps'))
  end)

  it('treats an empty trash table as enabled', function()
    vim.g.canola_trash = {}
    local orig_perform = files.perform_action
    local orig_render = files.render_action
    dofile(plugin_path)
    assert.is_true(has_registration(register_calls, 'canola-trash://', 'trash'))
    assert.not_equals(orig_perform, files.perform_action)
    assert.not_equals(orig_render, files.render_action)
    local err
    files.perform_action(
      { type = 'delete', url = 'oil:///tmp/file', entry_type = 'file' },
      function(e)
        err = e
      end
    )
    assert.is_nil(err)
    assert.are.same({ '/tmp/file' }, trash_deletes)
    assert.equals(
      ' TRASH /tmp/file',
      files.render_action({ type = 'delete', url = 'oil:///tmp/file', entry_type = 'file' })
    )
  end)

  it('does not enable trash from vim.g.canola.delete.trash', function()
    vim.g.canola = { delete = { trash = true } }
    local orig_perform = files.perform_action
    local orig_render = files.render_action
    dofile(plugin_path)
    assert.is_false(has_registration(register_calls, 'canola-trash://', 'trash'))
    assert.equals(orig_perform, files.perform_action)
    assert.equals(orig_render, files.render_action)
  end)

  it('treats an empty git table as enabled', function()
    vim.g.canola_git = {}
    dofile(plugin_path)
    assert.equals(1, git_init_calls)
  end)
end)
