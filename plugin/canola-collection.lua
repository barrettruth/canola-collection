local ok, canola = pcall(require, 'canola')
if not ok then
  return
end

---@param cfg unknown
---@return boolean
local function configured(cfg)
  return type(cfg) == 'table'
end

if configured(vim.g.canola_ssh) then
  canola.register_adapter('canola-ssh://', 'ssh')

  vim.api.nvim_create_autocmd('BufNew', {
    pattern = 'scp://*',
    once = true,
    callback = function()
      vim.notify('Use canola-ssh:// instead of scp://', vim.log.levels.WARN)
    end,
  })
end

if configured(vim.g.canola_s3) then
  canola.register_adapter('canola-s3://', 's3')

  if vim.fn.has('nvim-0.12') == 0 then
    canola.register_adapter('canola-sss://', 's3')
  end
end

if configured(vim.g.canola_ftp) then
  canola.register_adapter('canola-ftp://', 'ftp')
  canola.register_adapter('canola-ftps://', 'ftps')
end

if configured(vim.g.canola_trash) then
  canola.register_adapter('canola-trash://', 'trash')

  local files = require('canola.adapters.files')
  local fs = require('canola.fs')
  local util = require('canola.util')

  local orig_perform = files.perform_action
  files.perform_action = function(action, cb)
    if action.type == 'delete' then
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
    if action.type == 'delete' then
      local _, path = util.parse_url(action.url)
      assert(path)
      local short_path = files.to_short_os_path(path, action.entry_type)
      return string.format(' TRASH %s', short_path)
    else
      return orig_render(action)
    end
  end
end

if configured(vim.g.canola_git) then
  require('canola-git')._init()
end
