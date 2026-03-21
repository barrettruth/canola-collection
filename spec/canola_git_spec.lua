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

    it('skips is_hidden_file when enabled = false', function()
      vim.g.canola_git = { enabled = false }
      local call_count = 0
      local canola_mock = make_canola_mock(nil)
      canola_mock.set_is_hidden_file = function(_fn)
        call_count = call_count + 1
      end
      inject_mocks(canola_mock, make_git_mock(nil), make_view_mock())
      canola_git = require('canola-git')
      canola_git._init()
      assert.equals(0, call_count)
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
end)
