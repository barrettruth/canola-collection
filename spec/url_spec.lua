local canola = require('canola')

describe('url', function()
  before_each(function()
    require('canola.config').init()
    canola.register_adapter('canola-ssh://', 'ssh')
  end)

  it('parses ssh parent url', function()
    local output, basename =
      canola.get_buffer_parent_url('canola-ssh://user@hostname:8888//bar.txt', true)
    assert.equals('canola-ssh://user@hostname:8888//', output)
    assert.equals('bar.txt', basename)
  end)

  it('returns ssh root as-is', function()
    local output = canola.get_buffer_parent_url('canola-ssh://user@hostname:8888//', true)
    assert.equals('canola-ssh://user@hostname:8888//', output)
  end)
end)
