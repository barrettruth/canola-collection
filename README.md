# canola-collection

Optional adapters and extensions for
[canola.nvim](https://github.com/barrettruth/canola.nvim).

## Adapters

| Plugin       | Scheme(s)                         | Description                     |
| ------------ | --------------------------------- | ------------------------------- |
| canola-ssh   | `canola-ssh://`                   | Remote filesystem via SSH + SCP |
| canola-s3    | `canola-s3://`                    | AWS S3 via `aws` CLI            |
| canola-ftp   | `canola-ftp://`, `canola-ftps://` | FTP/FTPS via `curl`             |
| canola-trash | `canola-trash://`                 | OS-specific recycle bin         |
| canola-git   | n/a                               | Git status decoration (planned) |

## Extensions

| Plugin           | Description                        |
| ---------------- | ---------------------------------- |
| canola-resession | Session restore via resession.nvim |

## Installation

Requires [canola.nvim](https://github.com/barrettruth/canola.nvim) as a
dependency.

### lazy.nvim

```lua
{
  'barrettruth/canola-collection',
  dependencies = { 'barrettruth/canola.nvim' },
}
```

All adapters are lazy-loaded — they only activate when their URL scheme is first
accessed. No adapter code runs at startup.

## Configuration

Adapter-specific configuration lives in `vim.g.canola` alongside core settings:

```lua
vim.g.canola = {
  extra_scp_args = {},
  extra_s3_args = {},
  extra_curl_args = {},
  ssh_hosts = {},
  s3_buckets = {},
  ftp_hosts = {},
}
```

See `:help canola-collection` for full documentation.
