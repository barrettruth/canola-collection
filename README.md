# canola-collection

Optional adapters and extensions for [canola.nvim](https://github.com/barrettruth/canola.nvim).

## Adapters

| Plugin       | Scheme(s)                         | Description                     |
| ------------ | --------------------------------- | ------------------------------- |
| canola-ssh   | `canola-ssh://`                   | Remote filesystem via SSH + SCP |
| canola-s3    | `canola-s3://`                    | AWS S3 via `aws` CLI            |
| canola-ftp   | `canola-ftp://`, `canola-ftps://` | FTP/FTPS via `curl`             |
| canola-trash | `canola-trash://`                 | OS-specific recycle bin         |

## Extensions

| Plugin           | Description                        |
| ---------------- | ---------------------------------- |
| canola-resession | Session restore via resession.nvim |
| canola-git       | Git-aware hidden file filtering    |

## Installation

Install with your package manager of choice or via
[luarocks](https://luarocks.org/modules/barrettruth/canola-collection):

```
luarocks install canola-collection
```

Requires [canola.nvim](https://github.com/barrettruth/canola.nvim) as a dependency:

```lua
{
  'barrettruth/canola-collection',
  dependencies = { 'barrettruth/canola.nvim' },
}
```

## Documentation

```vim
:help canola-collection
```
