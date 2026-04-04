local ok, canola = pcall(require, 'canola')
if not ok then
  return
end

canola.register_adapter('canola-ssh://', 'ssh')
canola.register_adapter('canola-s3://', 's3')
canola.register_adapter('canola-trash://', 'trash')
canola.register_adapter('canola-ftp://', 'ftp')
canola.register_adapter('canola-ftps://', 'ftps')

if vim.fn.has('nvim-0.12') == 0 then
  canola.register_adapter('canola-sss://', 's3')
end

local config = require('canola.config')
local files = require('canola.adapters.files')
local fs = require('canola.fs')
local util = require('canola.util')

local orig_perform = files.perform_action
files.perform_action = function(action, cb)
  if action.type == 'delete' and config.delete.trash then
    local _, path = util.parse_url(action.url)
    assert(path)
    path = fs.posix_to_os_path(path)
    require('canola.adapters.trash').delete_to_trash(path, cb)
  else
    orig_perform(action, cb)
  end
end

local orig_render = files.render_action
files.render_action = function(action)
  if action.type == 'delete' and config.delete.trash then
    local _, path = util.parse_url(action.url)
    assert(path)
    local short_path = files.to_short_os_path(path, action.entry_type)
    return string.format(' TRASH %s', short_path)
  else
    return orig_render(action)
  end
end

require('canola-git')._init()

vim.api.nvim_create_autocmd('BufNew', {
  pattern = 'scp://*',
  once = true,
  callback = function()
    vim.notify('Use canola-ssh:// instead of scp://', vim.log.levels.WARN)
  end,
})
