rockspec_format = '3.0'
package = 'canola-collection'
version = 'scm-1'

source = {
  url = 'git+https://github.com/barrettruth/canola-collection.git',
}

description = {
  summary = 'Optional adapters and extensions for canola.nvim',
  homepage = 'https://github.com/barrettruth/canola-collection',
  license = 'MIT',
}

dependencies = {
  'lua >= 5.1',
}

test_dependencies = {
  'nlua',
  'busted >= 2.1.1',
}

test = {
  type = 'busted',
}

build = {
  type = 'builtin',
  copy_directories = { 'doc', 'plugin' },
}
