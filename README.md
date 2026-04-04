# canola-collection

Optional adapters and extensions for
[canola.nvim](https://github.com/barrettruth/canola.nvim). Install only what you
need — canola core ships with the local filesystem adapter only.

| Component                             | Description                            |
| ------------------------------------- | -------------------------------------- |
| [canola-git](#canola-git)             | Git-aware hiding + `git_status` column |
| [canola-ssh](#canola-ssh)             | Remote filesystem via SSH + SCP        |
| [canola-s3](#canola-s3)               | AWS S3 via `aws` CLI                   |
| [canola-ftp](#canola-ftp)             | FTP/FTPS via `curl`                    |
| [canola-trash](#canola-trash)         | OS-specific recycle bin                |
| [canola-resession](#canola-resession) | Session restore via resession.nvim     |

## Installation

Install with your package manager of choice or via
[luarocks](https://luarocks.org/modules/barrettruth/canola-collection):

```
luarocks install canola-collection
```

Adapters register themselves automatically on load. No `setup()` call needed.

## Configuration

Each component has its own `vim.g` table. All are optional — defaults work out
of the box.

### canola-git

Git-aware hidden file filtering and a `git_status` column. Tracked dotfiles
(`.gitignore`, `.github/`) stay visible. Gitignored files disappear. Directories
show the most severe status among their children.

```lua
vim.g.canola_git = {
  enabled = true,
  show = { untracked = true, ignored = false },
  format = 'compact', -- 'compact' | 'symbol' | 'porcelain'
}
```

Add the column to your canola config:

```lua
vim.g.canola = {
  columns = { 'git_status', 'icon' },
}
```

The cache refreshes automatically on mutations, focus changes, buffer entry, and
`:!` shell commands. To refresh manually:

```lua
require('canola-git').invalidate()
```

### canola-ssh

Browse remote filesystems via SSH. Uses SCP for file transfers.

```lua
vim.g.canola_ssh = {
  extra_args = {},
  border = nil,
  recursive = false,
  hosts = {
    ['nas.local'] = { extra_args = { '-O' } },
  },
}
```

Open with `:edit canola-ssh://user@host/path/`.

### canola-s3

Browse AWS S3 buckets via the `aws` CLI.

```lua
vim.g.canola_s3 = {
  extra_args = {},
  recursive = false,
  buckets = {
    ['my-r2'] = { extra_args = { '--endpoint-url', 'https://...' } },
  },
}
```

Open with `:edit canola-s3://bucket/prefix/`.

### canola-ftp

Browse FTP/FTPS servers via `curl`.

```lua
vim.g.canola_ftp = {
  extra_args = {},
  recursive = false,
  hosts = {
    ['ftp.example.com'] = { extra_args = { '--insecure' } },
  },
}
```

Open with `:edit canola-ftp://host/path/` or `canola-ftps://host/path/`.

### canola-trash

OS-specific recycle bin (freedesktop, macOS, Windows). No separate config —
enable it in canola:

```lua
vim.g.canola = {
  delete = { trash = true },
}
```

### canola-resession

Session restore via
[resession.nvim](https://github.com/stevearc/resession.nvim):

```lua
require('resession').setup({
  extensions = { canola = {} },
})
```

## Documentation

```
:help canola-collection
```
