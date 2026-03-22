local M = {}

---@param winid integer
---@param bufnr integer
---@return boolean
M.is_win_supported = function(winid, bufnr)
  return vim.bo[bufnr].filetype == 'canola'
end

---@param winid integer
---@return {bufname: string}
M.save_win = function(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  return { bufname = bufname }
end

---@param winid integer
---@param config {bufname: string}
M.load_win = function(winid, config)
  require('canola').open(config.bufname)
end

return M
