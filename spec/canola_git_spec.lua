local canola_git
local original_schedule

local function make_canola_mock(dir)
  return {
    get_current_dir = function(_bufnr)
      return dir
    end,
    set_is_hidden_file = function(_fn) end,
  }
end

local function make_git_mock(root)
  return {
    get_root = function(_path)
      return root
    end,
  }
end

local function make_view_mock()
  return {
    rerender_all_oil_buffers = function(_opts) end,
  }
end

local function make_columns_mock()
  return {
    register = function(_name, _def) end,
  }
end

local function inject_mocks(canola_mock, git_mock, view_mock)
  package.loaded['canola'] = canola_mock
  package.loaded['canola.git'] = git_mock
  package.loaded['canola.view'] = view_mock
  package.loaded['canola.columns'] = make_columns_mock()
  package.loaded['canola.constants'] = { FIELD_NAME = 2 }
end

local function clear_mocks()
  package.loaded['canola'] = nil
  package.loaded['canola.git'] = nil
  package.loaded['canola.view'] = nil
  package.loaded['canola.columns'] = nil
  package.loaded['canola.constants'] = nil
  package.loaded['canola-git'] = nil
  vim.g.canola_git = nil
end

describe('canola-git', function()
  before_each(function()
    clear_mocks()
    original_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end
  end)

  after_each(function()
    clear_mocks()
    vim.schedule = original_schedule
  end)

  describe('_init()', function()
    it('registers is_hidden_file override', function()
      local registered_fn = nil
      local canola_mock = make_canola_mock(nil)
      canola_mock.set_is_hidden_file = function(fn)
        registered_fn = fn
      end
      inject_mocks(canola_mock, make_git_mock(nil), make_view_mock())
      canola_git = require('canola-git')
      canola_git._init()
      assert.is_function(registered_fn)
    end)
  end)

  describe('is_hidden_file fallback (no cached data)', function()
    local hidden_fn

    before_each(function()
      local canola_mock = make_canola_mock('/some/dir')
      canola_mock.set_is_hidden_file = function(fn)
        hidden_fn = fn
      end
      inject_mocks(canola_mock, make_git_mock(nil), make_view_mock())
      canola_git = require('canola-git')
      canola_git._init()
    end)

    it('hides dotfiles by default before cache is populated', function()
      assert.is_true(hidden_fn('.gitignore', 1, {}))
    end)

    it('shows non-dotfiles by default before cache is populated', function()
      assert.is_false(hidden_fn('readme.md', 1, {}))
    end)
  end)

  describe('is_hidden_file fallback (non-git dir)', function()
    local hidden_fn

    before_each(function()
      local canola_mock = make_canola_mock(nil)
      canola_mock.set_is_hidden_file = function(fn)
        hidden_fn = fn
      end
      inject_mocks(canola_mock, make_git_mock(nil), make_view_mock())
      canola_git = require('canola-git')
      canola_git._init()
    end)

    it('hides dotfiles when get_current_dir returns nil', function()
      assert.is_true(hidden_fn('.env', 1, {}))
    end)

    it('shows non-dotfiles when get_current_dir returns nil', function()
      assert.is_false(hidden_fn('main.lua', 1, {}))
    end)
  end)

  describe('is_hidden_file with populated cache', function()
    local hidden_fn
    local cache_dir = '/repo'

    before_each(function()
      local canola_mock = make_canola_mock(cache_dir)
      canola_mock.set_is_hidden_file = function(fn)
        hidden_fn = fn
      end
      inject_mocks(canola_mock, make_git_mock('/repo'), make_view_mock())
      canola_git = require('canola-git')
      canola_git._init()
    end)

    it('shows tracked dotfiles', function()
      canola_git._cache = { [cache_dir] = { tracked = { ['.gitignore'] = true }, ignored = {} } }
      assert.is_false(hidden_fn('.gitignore', 1, {}))
    end)

    it('hides untracked dotfiles', function()
      canola_git._cache = { [cache_dir] = { tracked = {}, ignored = {} } }
      assert.is_true(hidden_fn('.env', 1, {}))
    end)

    it('hides git-ignored non-dotfiles', function()
      canola_git._cache = { [cache_dir] = { tracked = {}, ignored = { ['dist'] = true } } }
      assert.is_true(hidden_fn('dist', 1, {}))
    end)

    it('shows non-dotfiles that are not ignored', function()
      canola_git._cache = { [cache_dir] = { tracked = {}, ignored = {} } }
      assert.is_false(hidden_fn('src', 1, {}))
    end)

    it('shows non-dotfiles that are tracked and not ignored', function()
      canola_git._cache = {
        [cache_dir] = { tracked = { ['README.md'] = true }, ignored = {} },
      }
      assert.is_false(hidden_fn('README.md', 1, {}))
    end)

    it('hides non-dotfile that is both ignored and not tracked', function()
      canola_git._cache = {
        [cache_dir] = { tracked = {}, ignored = { ['node_modules'] = true } },
      }
      assert.is_true(hidden_fn('node_modules', 1, {}))
    end)
  end)

  describe('get_status()', function()
    before_each(function()
      inject_mocks(make_canola_mock('/repo'), make_git_mock('/repo'), make_view_mock())
      canola_git = require('canola-git')
      canola_git._init()
    end)

    it('returns nil for uncached directory', function()
      assert.is_nil(canola_git.get_status('/repo', 'file.lua'))
    end)

    it('returns nil for unknown file', function()
      canola_git._cache = { ['/repo'] = { status = {}, tracked = {}, ignored = {} } }
      assert.is_nil(canola_git.get_status('/repo', 'file.lua'))
    end)

    it('returns index field for staged change', function()
      canola_git._cache =
        { ['/repo'] = { status = { ['file.lua'] = 'M ' }, tracked = {}, ignored = {} } }
      local result = canola_git.get_status('/repo', 'file.lua')
      assert.equals('M', result.index)
      assert.is_nil(result.worktree)
    end)

    it('returns worktree field for unstaged change', function()
      canola_git._cache =
        { ['/repo'] = { status = { ['file.lua'] = ' M' }, tracked = {}, ignored = {} } }
      local result = canola_git.get_status('/repo', 'file.lua')
      assert.is_nil(result.index)
      assert.equals('M', result.worktree)
    end)

    it('returns both index and worktree for staged+unstaged', function()
      canola_git._cache =
        { ['/repo'] = { status = { ['file.lua'] = 'AM' }, tracked = {}, ignored = {} } }
      local result = canola_git.get_status('/repo', 'file.lua')
      assert.equals('A', result.index)
      assert.equals('M', result.worktree)
      assert.equals('AM', result.status)
      assert.equals('A', result.char)
    end)
  end)

  describe('git_status column render', function()
    local render_fn

    before_each(function()
      local columns_mock = {
        register = function(_name, def)
          render_fn = def.render
        end,
      }
      package.loaded['canola'] = make_canola_mock('/repo')
      package.loaded['canola.git'] = make_git_mock('/repo')
      package.loaded['canola.view'] = make_view_mock()
      package.loaded['canola.columns'] = columns_mock
      package.loaded['canola.constants'] = { FIELD_NAME = 2 }
      canola_git = require('canola-git')
      canola_git._init()
    end)

    it('returns range-based highlights for porcelain format', function()
      vim.g.canola_git = { format = 'porcelain' }
      canola_git._cache =
        { ['/repo'] = { status = { ['file.lua'] = 'AM' }, tracked = {}, ignored = {} } }
      local result = render_fn({ nil, 'file.lua' }, {}, 0)
      assert.equals('AM', result[1])
      assert.same({ { 'DiagnosticOk', 0, 1 }, { 'DiagnosticWarn', 1, 2 } }, result[2])
    end)

    it('returns single highlight for compact format', function()
      canola_git._cache =
        { ['/repo'] = { status = { ['file.lua'] = ' M' }, tracked = {}, ignored = {} } }
      local result = render_fn({ nil, 'file.lua' }, {}, 0)
      assert.equals('M', result[1])
      assert.equals('DiagnosticWarn', result[2])
    end)

    it('returns nil for file without status', function()
      canola_git._cache = { ['/repo'] = { status = {}, tracked = {}, ignored = {} } }
      local result = render_fn({ nil, 'clean.lua' }, {}, 0)
      assert.is_nil(result)
    end)
  end)

  describe('cache refresh and CanolaGitUpdate', function()
    local tmpdir
    local autocmds
    local fired_events
    local order
    local system_outputs
    local original_create_autocmd
    local original_exec_autocmds
    local original_now
    local original_system
    local fake_now

    local function has_event(event, expected)
      if type(event) == 'table' then
        return vim.tbl_contains(event, expected)
      else
        return event == expected
      end
    end

    local function get_autocmd(expected_event, pattern)
      for _, autocmd in ipairs(autocmds) do
        if has_event(autocmd.event, expected_event) and autocmd.opts.pattern == pattern then
          return autocmd.opts.callback
        end
      end
    end

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
      autocmds = {}
      fired_events = {}
      order = {}
      system_outputs = {
        ['git ls-files'] = {
          code = 0,
          stdout = table.concat({ 'sub/file.lua', 'old.lua', 'new.lua', 'conflict.lua' }, '\n'),
        },
        ['git ls-files --ignored --exclude-standard --others --directory'] = {
          code = 0,
          stdout = 'build/\n',
        },
        ['git --no-optional-locks status --porcelain -- .'] = {
          code = 0,
          stdout = table.concat({
            ' M sub/file.lua',
            'R  old.lua -> new.lua',
            'UU conflict.lua',
            '?? fresh.lua',
          }, '\n'),
        },
      }

      original_create_autocmd = vim.api.nvim_create_autocmd
      original_exec_autocmds = vim.api.nvim_exec_autocmds
      original_now = vim.uv.now
      original_system = vim.system
      fake_now = 1000

      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(autocmds, { event = event, opts = opts })
        return #autocmds
      end

      vim.api.nvim_exec_autocmds = function(event, opts)
        table.insert(order, 'event')
        table.insert(fired_events, { event = event, opts = opts })
      end

      vim.uv.now = function()
        return fake_now
      end

      vim.system = function(cmd, _opts, callback)
        local key = table.concat(cmd, ' ')
        local result = assert(system_outputs[key], key)
        callback(result)
        return {}
      end

      inject_mocks(make_canola_mock(tmpdir), make_git_mock(tmpdir), {
        rerender_all_oil_buffers = function(_opts)
          table.insert(order, 'rerender')
        end,
      })
      canola_git = require('canola-git')
      canola_git._init()
    end)

    after_each(function()
      vim.api.nvim_create_autocmd = original_create_autocmd
      vim.api.nvim_exec_autocmds = original_exec_autocmds
      vim.uv.now = original_now
      vim.system = original_system
      if tmpdir then
        vim.fn.delete(tmpdir, 'rf')
      end
    end)

    it('stores raw path status data and emits CanolaGitUpdate before rerender', function()
      local callback = assert(get_autocmd('User', 'CanolaReadPost'))
      callback({ data = { buf = 1 } })

      local cache = canola_git._cache[tmpdir]
      assert.equals(tmpdir, cache.root)
      assert.equals(' M', cache.status.sub)
      assert.equals('R ', cache.status['new.lua'])
      assert.is_true(cache.ignored.build)
      assert.is_true(cache.tracked.sub)

      assert.same({
        status = ' M',
        char = 'M',
        type = 'modified',
        index = nil,
        worktree = 'M',
        source_path = nil,
      }, cache.path_status['sub/file.lua'])
      assert.same({
        status = 'R ',
        char = 'R',
        type = 'renamed',
        index = 'R',
        worktree = nil,
        source_path = 'old.lua',
      }, cache.path_status['new.lua'])
      assert.same({
        status = 'UU',
        char = 'U',
        type = 'unmerged',
        index = 'U',
        worktree = 'U',
        source_path = nil,
      }, cache.path_status['conflict.lua'])
      assert.same({
        status = '??',
        char = '?',
        type = 'untracked',
        index = '?',
        worktree = '?',
        source_path = nil,
      }, cache.path_status['fresh.lua'])

      assert.equals('User', fired_events[1].event)
      assert.equals('CanolaGitUpdate', fired_events[1].opts.pattern)
      assert.same({ dir = tmpdir, root = tmpdir, reason = 'initial' }, fired_events[1].opts.data)
      assert.same({ 'event', 'rerender' }, order)
    end)

    it('prefers initial over buf_enter before canola_ready', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buf_enter = assert(get_autocmd('BufEnter'))
      local read_post = assert(get_autocmd('User', 'CanolaReadPost'))

      vim.bo[bufnr].filetype = 'canola'

      buf_enter({ buf = bufnr })

      assert.is_nil(canola_git._cache[tmpdir])
      assert.same({}, fired_events)

      read_post({ data = { buf = bufnr } })

      assert.equals('initial', fired_events[1].opts.data.reason)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('refreshes on buf_enter after canola_ready when cache is stale', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buf_enter = assert(get_autocmd('BufEnter'))
      local read_post = assert(get_autocmd('User', 'CanolaReadPost'))

      vim.bo[bufnr].filetype = 'canola'

      read_post({ data = { buf = bufnr } })

      fired_events = {}
      order = {}
      vim.b[bufnr].canola_ready = true
      fake_now = 4001

      buf_enter({ buf = bufnr })

      assert.equals('CanolaGitUpdate', fired_events[1].opts.pattern)
      assert.equals('buf_enter', fired_events[1].opts.data.reason)
      assert.same({ 'event', 'rerender' }, order)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('uses manual as the default invalidate reason', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = 'canola'

      canola_git.invalidate()

      assert.equals('CanolaGitUpdate', fired_events[1].opts.pattern)
      assert.equals('manual', fired_events[1].opts.data.reason)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('non-git cache refresh', function()
    local tmpdir
    local autocmds
    local fired_events
    local original_create_autocmd
    local original_exec_autocmds

    local function get_autocmd(expected_event, pattern)
      for _, autocmd in ipairs(autocmds) do
        if autocmd.event == expected_event and autocmd.opts.pattern == pattern then
          return autocmd.opts.callback
        end
      end
    end

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
      autocmds = {}
      fired_events = {}

      original_create_autocmd = vim.api.nvim_create_autocmd
      original_exec_autocmds = vim.api.nvim_exec_autocmds

      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(autocmds, { event = event, opts = opts })
        return #autocmds
      end

      vim.api.nvim_exec_autocmds = function(event, opts)
        table.insert(fired_events, { event = event, opts = opts })
      end

      inject_mocks(make_canola_mock(tmpdir), make_git_mock(nil), make_view_mock())
      canola_git = require('canola-git')
      canola_git._init()
    end)

    after_each(function()
      vim.api.nvim_create_autocmd = original_create_autocmd
      vim.api.nvim_exec_autocmds = original_exec_autocmds
      if tmpdir then
        vim.fn.delete(tmpdir, 'rf')
      end
    end)

    it('stores false and does not emit CanolaGitUpdate', function()
      local callback = assert(get_autocmd('User', 'CanolaReadPost'))
      callback({ data = { buf = 1 } })

      assert.is_false(canola_git._cache[tmpdir])
      assert.same({}, fired_events)
    end)
  end)
end)
