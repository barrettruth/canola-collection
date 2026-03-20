local ext = require('resession.extensions.canola')

describe('resession extension', function()
  local function make_buf(filetype, name)
    local bufnr = vim.api.nvim_create_buf(false, true)
    if filetype then
      vim.bo[bufnr].filetype = filetype
    end
    if name then
      vim.api.nvim_buf_set_name(bufnr, name)
    end
    return bufnr
  end

  local function make_win_with_buf(bufnr)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    return winid
  end

  after_each(function()
    package.loaded['canola'] = nil
  end)

  describe('is_win_supported', function()
    it('returns true when filetype is canola', function()
      local bufnr = make_buf('canola')
      assert.is_true(ext.is_win_supported(1000, bufnr))
    end)

    it('returns false when filetype is lua', function()
      local bufnr = make_buf('lua')
      assert.is_false(ext.is_win_supported(1000, bufnr))
    end)

    it('returns false when filetype is empty', function()
      local bufnr = make_buf()
      assert.is_false(ext.is_win_supported(1000, bufnr))
    end)

    it('returns false when filetype is oil', function()
      local bufnr = make_buf('oil')
      assert.is_false(ext.is_win_supported(1000, bufnr))
    end)

    it('returns false when filetype is a prefix of canola', function()
      local bufnr = make_buf('can')
      assert.is_false(ext.is_win_supported(1000, bufnr))
    end)

    it('returns false when filetype is a superset of canola', function()
      local bufnr = make_buf('canola2')
      assert.is_false(ext.is_win_supported(1000, bufnr))
    end)

    it('is case-sensitive', function()
      local bufnr = make_buf('Canola')
      assert.is_false(ext.is_win_supported(1000, bufnr))
    end)
  end)

  describe('save_win', function()
    it('returns bufname for a named canola buffer', function()
      local bufnr = make_buf('canola', 'canola-ssh://host/path/')
      local winid = make_win_with_buf(bufnr)
      local config = ext.save_win(winid)
      assert.equals('canola-ssh://host/path/', config.bufname)
    end)

    it('returns empty string bufname for unnamed buffer', function()
      local bufnr = make_buf('canola')
      local winid = make_win_with_buf(bufnr)
      local config = ext.save_win(winid)
      assert.equals('', config.bufname)
    end)

    it('returns a table with a bufname key', function()
      local bufnr = make_buf('canola', 'canola-ftp://user@host/dir/')
      local winid = make_win_with_buf(bufnr)
      local config = ext.save_win(winid)
      assert.is_table(config)
      assert.is_not_nil(config.bufname)
    end)

    it('saves bufname regardless of filetype', function()
      local bufnr = make_buf('lua', 'canola-ssh://otherhost/path/')
      local winid = make_win_with_buf(bufnr)
      local config = ext.save_win(winid)
      assert.equals('canola-ssh://otherhost/path/', config.bufname)
    end)

    it('reflects the buffer actually in the window, not an arbitrary buffer', function()
      local bufnr_a = make_buf('canola', 'canola-ssh://host/a/')
      local bufnr_b = make_buf('canola', 'canola-ssh://host/b/')
      local winid = make_win_with_buf(bufnr_a)
      local config_a = ext.save_win(winid)

      vim.api.nvim_win_set_buf(winid, bufnr_b)
      local config_b = ext.save_win(winid)

      assert.equals('canola-ssh://host/a/', config_a.bufname)
      assert.equals('canola-ssh://host/b/', config_b.bufname)
    end)
  end)

  describe('load_win', function()
    it('calls canola.open with the config bufname', function()
      local called_with = nil
      package.loaded['canola'] = {
        open = function(name)
          called_with = name
        end,
      }
      ext.load_win(1000, { bufname = 'canola-ssh://host/path/' })
      assert.equals('canola-ssh://host/path/', called_with)
    end)

    it('calls canola.open with an empty bufname', function()
      local called_with = 'sentinel'
      package.loaded['canola'] = {
        open = function(name)
          called_with = name
        end,
      }
      ext.load_win(1000, { bufname = '' })
      assert.equals('', called_with)
    end)

    it('passes bufname unchanged for ftp url', function()
      local called_with = nil
      package.loaded['canola'] = {
        open = function(name)
          called_with = name
        end,
      }
      ext.load_win(1000, { bufname = 'canola-ftp://user:pass@host:2121/dir/' })
      assert.equals('canola-ftp://user:pass@host:2121/dir/', called_with)
    end)

    it('passes bufname unchanged for s3 url', function()
      local called_with = nil
      package.loaded['canola'] = {
        open = function(name)
          called_with = name
        end,
      }
      ext.load_win(1000, { bufname = 'canola-s3://my-bucket//some/key' })
      assert.equals('canola-s3://my-bucket//some/key', called_with)
    end)

    it('ignores the winid argument', function()
      local open_count = 0
      package.loaded['canola'] = {
        open = function(_)
          open_count = open_count + 1
        end,
      }
      ext.load_win(9999, { bufname = 'canola-ssh://host/' })
      assert.equals(1, open_count)
    end)
  end)

  describe('save and load round-trip', function()
    it('restores the same url after a save/load cycle', function()
      local url = 'canola-ssh://user@hostname:8888//some/path/'
      local bufnr = make_buf('canola', url)
      local winid = make_win_with_buf(bufnr)

      local config = ext.save_win(winid)

      local restored = nil
      package.loaded['canola'] = {
        open = function(name)
          restored = name
        end,
      }
      ext.load_win(winid, config)

      assert.equals(url, restored)
    end)

    it('round-trips an ftp url with credentials', function()
      local url = 'canola-ftp://user:pass@host:21/dir/'
      local bufnr = make_buf('canola', url)
      local winid = make_win_with_buf(bufnr)

      local config = ext.save_win(winid)
      assert.equals(url, config.bufname)

      local restored = nil
      package.loaded['canola'] = {
        open = function(name)
          restored = name
        end,
      }
      ext.load_win(winid, config)
      assert.equals(url, restored)
    end)
  end)
end)
