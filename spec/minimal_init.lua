vim.cmd([[set runtimepath=$VIMRUNTIME]])
local canola_path = vim.fn.expand('~/dev/canola.nvim')
vim.opt.runtimepath:append(canola_path)
vim.opt.runtimepath:append('.')
vim.opt.packpath = {}
vim.o.swapfile = false
vim.cmd('filetype on')
vim.fn.mkdir(vim.fn.stdpath('cache'), 'p')
vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
vim.fn.mkdir(vim.fn.stdpath('state'), 'p')
