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
